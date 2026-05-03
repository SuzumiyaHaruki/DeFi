// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DeFi} from "../src/Vault.sol";
import {Token} from "../src/Token.sol";

contract DeFiTest is Test {
    Token token;
    DeFi defi;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address admin = address(0xAD);

    function setUp() public {
        token = new Token("Suzumiya", "SOS", 1_000_000 ether);
        defi = new DeFi(token);

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(admin, 10 ether);
    }

    function testDepositRecordsUserBalanceAndTotalDeposits() public {
        vm.prank(alice);
        defi.deposit{value: 2 ether}();

        (, uint256 aliceBalance, bool aliceExists) = defi.map(alice);

        assertTrue(aliceExists);
        assertEq(aliceBalance, 2 ether);
        assertEq(defi.totalDeposits(), 2 ether);
        assertEq(address(defi).balance, 2 ether);
    }

    function testWithdrawSendsEthAndUpdatesAccounting() public {
        vm.startPrank(alice);
        defi.deposit{value: 2 ether}();

        uint256 aliceEthBefore = alice.balance;
        defi.withdraw(0.75 ether);
        vm.stopPrank();

        (, uint256 aliceVaultBalance,) = defi.map(alice);

        assertEq(alice.balance, aliceEthBefore + 0.75 ether);
        assertEq(aliceVaultBalance, 1.25 ether);
        assertEq(defi.totalDeposits(), 1.25 ether);
        assertEq(address(defi).balance, 1.25 ether);
    }

    function testTransferMovesInternalBalanceAndRejectsZeroAddress() public {
        vm.startPrank(alice);
        defi.deposit{value: 2 ether}();

        vm.expectRevert("Invalid recipient");
        defi.transfer(address(0), 1 ether);

        defi.transfer(bob, 1 ether);
        vm.stopPrank();

        (, uint256 aliceBalance,) = defi.map(alice);
        (, uint256 bobBalance, bool bobExists) = defi.map(bob);

        assertEq(aliceBalance, 1 ether);
        assertEq(bobBalance, 1 ether);
        assertTrue(bobExists);
        assertEq(defi.totalDeposits(), 2 ether);
    }

    function testOnlyOwnerCanSetAdmin() public {
        vm.prank(alice);
        vm.expectRevert("Only owner can use this function!");
        defi.setAdmin(admin);

        defi.setAdmin(admin);

        assertTrue(defi.isAdmin(admin));
    }

    function testYieldDistributionCanRunInPages() public {
        vm.prank(alice);
        defi.deposit{value: 1 ether}();

        vm.prank(bob);
        defi.deposit{value: 3 ether}();

        token.transfer(address(defi), 400 ether);

        defi.startYieldDistribution();

        assertTrue(defi.yieldDistributionActive());
        assertEq(defi.yieldSnapshot(), 400 ether);
        assertEq(defi.depositSnapshot(), 4 ether);

        defi.distributeYield(2);

        assertTrue(defi.yieldDistributionActive());
        assertEq(defi.yieldCursor(), 2);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(bob), 0);

        defi.distributeYield(2);

        assertFalse(defi.yieldDistributionActive());
        assertEq(defi.yieldCursor(), 3);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(bob), 300 ether);
        assertEq(defi.distributedYield(), 400 ether);
    }

    function testCannotChangeBalancesDuringYieldDistribution() public {
        vm.prank(alice);
        defi.deposit{value: 1 ether}();

        token.transfer(address(defi), 100 ether);
        defi.startYieldDistribution();

        vm.startPrank(alice);

        vm.expectRevert("Yield distribution active");
        defi.deposit{value: 1 ether}();

        vm.expectRevert("Yield distribution active");
        defi.withdraw(1 ether);

        vm.expectRevert("Yield distribution active");
        defi.transfer(bob, 1 ether);

        vm.stopPrank();
    }

    function testOnlyAdminCanDistributeYield() public {
        vm.prank(alice);
        defi.deposit{value: 1 ether}();

        token.transfer(address(defi), 100 ether);

        vm.prank(alice);
        vm.expectRevert("Only admin can use this function!");
        defi.startYieldDistribution();

        defi.setAdmin(admin);

        vm.prank(admin);
        defi.startYieldDistribution();

        vm.prank(alice);
        vm.expectRevert("Only admin can use this function!");
        defi.distributeYield(1);
    }
}
