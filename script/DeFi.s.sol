// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {DeFi} from "../src/Vault.sol";
import {Token} from "../src/Token.sol";

contract DefiScript is Script {
    DeFi defi;
    Token public token;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        token = new Token("Suzumiya", "SOS", 10000 ether);
        defi = new DeFi(token);
        token.mint(address(defi), 100 ether);
        vm.stopBroadcast();
    }
}
