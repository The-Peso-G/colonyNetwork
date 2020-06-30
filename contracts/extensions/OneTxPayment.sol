/*
  This file is part of The Colony Network.

  The Colony Network is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  The Colony Network is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with The Colony Network. If not, see <http://www.gnu.org/licenses/>.
*/

pragma solidity 0.5.8;
pragma experimental ABIEncoderV2;

import "./../colony/ColonyDataTypes.sol";
import "./../colony/IColony.sol";

// ignore-file-swc-108


contract OneTxPayment {
  uint256 constant UINT256_MAX = 2**256 - 1;

  IColony colony;

  constructor(address _colony) public {
    colony = IColony(_colony);
  }

  /// @notice Completes a colony payment in a single transaction
  /// @dev Assumes that each entity holds administration and funding roles in the root domain
  /// @param _permissionDomainId The domainId in which the _contract_ has permissions to add a payment and fund it
  /// @param _childSkillIndex Index of the _permissionDomainId skill.children array to get
  /// @param _callerPermissionDomainId The domainId in which the _caller_ has permissions to add a payment and fund it
  /// @param _callerChildSkillIndex Index of the _callerPermissionDomainId skill.children array to get
  /// @param _workers The addresses of the recipients of the payment
  /// @param _tokens Addresses of the tokens the payments are being made in. 0x00 for Ether.
  /// @param _amounts amounts of the tokens being paid out
  /// @param _domainId The domainId the payment should be coming from
  /// @param _skillId The skillId that the payment should be marked with, possibly awarding reputation in this skill.
  function makePayment(
    uint256 _permissionDomainId, // Unused
    uint256 _childSkillIndex,
    uint256 _callerPermissionDomainId, // Unused
    uint256 _callerChildSkillIndex, // Unused
    address payable[] memory _workers,
    address[] memory _tokens,
    uint256[] memory _amounts,
    uint256 _domainId,
    uint256 _skillId
  )
    public
  {
    require(_workers.length == _tokens.length && _workers.length == _amounts.length, "colony-one-tx-payment-invalid-input");
    validatePermissions(1, _childSkillIndex, _domainId);

    if (_workers.length == 1) {

      uint256 paymentId = colony.addPayment(1, _childSkillIndex, _workers[0], _tokens[0], _amounts[0], _domainId, _skillId);
      uint256 fundingPotId = colony.getPayment(paymentId).fundingPotId;

      colony.moveFundsBetweenPots(1, UINT256_MAX, _childSkillIndex, 1, fundingPotId, _amounts[0], _tokens[0]);

      colony.finalizePayment(1, _childSkillIndex, paymentId);
      colony.claimPayment(paymentId, _tokens[0]);

    } else {

      uint256 expenditureId = colony.makeExpenditure(1, _childSkillIndex, _domainId);
      uint256 fundingPotId = colony.getExpenditure(expenditureId).fundingPotId;

      uint256 idx;
      uint256 slot;

      for (idx = 0; idx < _workers.length; idx++) {
        colony.moveFundsBetweenPots(1, UINT256_MAX, _childSkillIndex, 1, fundingPotId, _amounts[idx], _tokens[idx]);

         // If a new worker, start a new slot
        if (idx == 0 || _workers[idx] != _workers[idx-1]) {
          slot++;
          colony.setExpenditureRecipient(expenditureId, slot, _workers[idx]);

          if (_skillId != 0) {
            colony.setExpenditureSkill(expenditureId, slot, _skillId);
          }
        }

        colony.setExpenditurePayout(expenditureId, slot, _tokens[idx], _amounts[idx]);
      }

      finalizeAndClaim(expenditureId, _workers, _tokens);

    }
  }

  /// @notice Completes a colony payment in a single transaction
  /// @dev Assumes that each entity holds administration and funding roles in the same domain,
  ///   although contract and caller can have the permissions in different domains.
  /// Payment is taken from domain funds - if the domain does not have sufficient funds, call will fail.
  /// @param _permissionDomainId The domainId in which the _contract_ has permissions to add a payment and fund it
  /// @param _childSkillIndex Index of the _permissionDomainId skill.children array to get
  /// @param _callerPermissionDomainId The domainId in which the _caller_ has permissions to add a payment and fund it
  /// @param _callerChildSkillIndex Index of the _callerPermissionDomainId skill.children array to get
  /// @param _workers The addresses of the recipients of the payment
  /// @param _tokens The addresses of the token the payments are being made in. 0x00 for Ether.
  /// @param _amounts The amounts of the tokens being paid out
  /// @param _domainId The domainId the payment should be coming from
  /// @param _skillId The skillId that the payment should be marked with, possibly awarding reputation in this skill.
  function makePaymentFundedFromDomain(
    uint256 _permissionDomainId,
    uint256 _childSkillIndex,
    uint256 _callerPermissionDomainId,
    uint256 _callerChildSkillIndex,
    address payable[] memory  _workers,
    address[] memory _tokens,
    uint256[] memory _amounts,
    uint256 _domainId,
    uint256 _skillId
  )
    public
  {
    require(_workers.length == _tokens.length && _workers.length == _amounts.length, "colony-one-tx-payment-invalid-input");
    validatePermissions(_callerPermissionDomainId, _callerChildSkillIndex, _domainId);

    if (_workers.length == 1) {

      uint256 paymentId = colony.addPayment(_permissionDomainId, _childSkillIndex, _workers[0], _tokens[0], _amounts[0], _domainId, _skillId);
      uint256 fundingPotId = colony.getPayment(paymentId).fundingPotId;
      uint256 domainPotId = colony.getDomain(_domainId).fundingPotId;

      moveFundsWithinDomain(_permissionDomainId, _childSkillIndex, domainPotId, fundingPotId, _amounts[0], _tokens[0]);

      colony.finalizePayment(_permissionDomainId, _childSkillIndex, paymentId);
      colony.claimPayment(paymentId, _tokens[0]);

    } else {

      uint256 expenditureId = colony.makeExpenditure(_permissionDomainId, _childSkillIndex, _domainId);
      uint256 fundingPotId = colony.getExpenditure(expenditureId).fundingPotId;
      uint256 domainPotId = colony.getDomain(_domainId).fundingPotId;

      uint256 idx;
      uint256 slot;

      for (idx = 0; idx < _workers.length; idx++) {
        moveFundsWithinDomain(_permissionDomainId, _childSkillIndex, domainPotId, fundingPotId, _amounts[idx], _tokens[idx]);

         // If a new worker, start a new slot
        if (idx == 0 || _workers[idx] != _workers[idx-1]) {
          slot++;
          colony.setExpenditureRecipient(expenditureId, slot, _workers[idx]);

          if (_skillId != 0) {
            colony.setExpenditureSkill(expenditureId, slot, _skillId);
          }
        }

        colony.setExpenditurePayout(expenditureId, slot, _tokens[idx], _amounts[idx]);
      }

      finalizeAndClaim(expenditureId, _workers, _tokens);

    }
  }

  function moveFundsWithinDomain(
    uint256 _permissionDomainId,
    uint256 _childSkillIndex,
    uint256 _domainPotId,
    uint256 _fundingPotId,
    uint256 _amount,
    address _token
  )
    internal
  {
    colony.moveFundsBetweenPots(_permissionDomainId, _childSkillIndex, _childSkillIndex, _domainPotId, _fundingPotId, _amount, _token);
  }

  function finalizeAndClaim(uint256 _expenditureId, address payable[] memory  _workers, address[] memory _tokens) internal {
    colony.finalizeExpenditure(_expenditureId);

    uint256 slot;

    for (uint256 idx; idx < _workers.length; idx++) {
      if (idx == 0 || _workers[idx] != _workers[idx-1]) {
        slot++;
      }
      colony.claimExpenditurePayout(_expenditureId, slot, _tokens[idx]);
    }
  }

  function validatePermissions(uint256 _permissionDomainId, uint256 _childSkillIndex, uint256 _domainId)
    internal
    view
  {
    require(
      colony.hasInheritedUserRole(msg.sender, _permissionDomainId, ColonyDataTypes.ColonyRole.Funding, _childSkillIndex, _domainId) &&
      colony.hasInheritedUserRole(msg.sender, _permissionDomainId, ColonyDataTypes.ColonyRole.Administration, _childSkillIndex, _domainId),
      "colony-one-tx-payment-not-authorized"
    );
  }
}
