// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { VaultFactory } from "../../../contracts/VaultFactory.sol";
import { VaultExtensionMock } from "../../../contracts/test/VaultExtensionMock.sol";
import { VaultMock } from "../../../contracts/test/VaultMock.sol";

library VaultMockDeployer {
    function deploy() internal returns (VaultMock vault) {
        IAuthorizer authorizer = new BasicAuthorizerMock();
        bytes32 salt = bytes32(0);
        vault = VaultMock(payable(CREATE3.getDeployed(salt)));
        VaultExtensionMock vaultExtension = new VaultExtensionMock(IVault(address(vault)));
        _create(abi.encode(vaultExtension, authorizer, 90 days, 30 days), salt);
        return vault;
    }

    function _create(bytes memory constructorArgs, bytes32 salt) internal returns (address) {
        return CREATE3.deploy(salt, abi.encodePacked(type(VaultMock).creationCode, constructorArgs), 0);
    }
}