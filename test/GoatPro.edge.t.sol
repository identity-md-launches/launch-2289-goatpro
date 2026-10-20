// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {GoatPro} from "src/GoatPro.sol";

/// @dev Complements the deployment and ordinary ERC-20 cases in GoatPro.t.sol.
/// forge-config: default.fuzz.runs = 1000
contract GoatProEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    GoatPro private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        deployer = makeAddr("edge deployer");
        alice = makeAddr("edge alice");
        bob = makeAddr("edge bob");
        spender = makeAddr("edge spender");
        vm.prank(deployer);
        token = new GoatPro();
    }

    function test_OneBaseUnitRoundTripRestoresBalances() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, 1));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferRevertsWithoutChangingApproval() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DelegatedFullSupplyTransferCannotBeRepeated() public {
        vm.prank(deployer);
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(deployer, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteApprovalIsDecreased() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 2);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_UnlimitedApprovalCanBeReplacedWithFiniteApproval() public {
        vm.startPrank(deployer);
        token.approve(spender, type(uint256).max);
        token.approve(spender, 3);
        vm.stopPrank();
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), 2);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 3);
        assertEq(token.allowance(deployer, spender), 2);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_UnlimitedApprovalCannotSpendAnExhaustedBalance() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, SUPPLY));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_OwnerCallingTransferFromStillNeedsSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        vm.startPrank(deployer);
        token.approve(deployer, 1);
        assertTrue(token.transferFrom(deployer, alice, 1));
        vm.stopPrank();
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_SpenderCanBeTheRecipientWithoutOwningTokens() public {
        vm.prank(deployer);
        token.approve(spender, 7);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, spender, 7));
        assertEq(token.balanceOf(deployer), SUPPLY - 7);
        assertEq(token.balanceOf(spender), 7);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.allowance(spender, deployer), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferEmitsEventAndPreservesFiniteApproval() public {
        vm.prank(alice);
        token.approve(spender, 17);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 17);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroSpenderIsRejectedEvenForZeroApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 0);
        assertEq(token.allowance(deployer, address(0)), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_ZeroRecipientIsRejectedEvenForZeroDelegatedTransfer() public {
        vm.prank(deployer);
        token.approve(spender, 17);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 0);
        assertEq(token.allowance(deployer, spender), 17);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroOwnerCannotBeUsedAsAMintSource() public {
        // Zero value bypasses the insufficient-allowance check but must still be rejected.
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 1);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalBeforeFundingSurvivesFailureAndCanLaterBeSpent() public {
        vm.prank(alice);
        token.approve(spender, 9);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 9));
        vm.prank(spender);
        token.transferFrom(alice, bob, 9);
        assertEq(token.allowance(alice, spender), 9);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(deployer);
        token.transfer(alice, 9);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 9));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - 9);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 9);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsIdempotentAndIsolated(uint256 initialApproval, uint256 replacement) public {
        vm.startPrank(deployer);
        token.approve(spender, initialApproval);
        token.approve(bob, 11);
        vm.stopPrank();
        vm.prank(alice);
        token.approve(spender, 13);

        vm.startPrank(deployer);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(deployer, spender), replacement, "approval must replace, not add");
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), replacement);
        assertEq(token.allowance(deployer, bob), 11);
        assertEq(token.allowance(alice, spender), 13);
        assertEq(token.allowance(spender, deployer), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_BalanceFailureRestoresAnyFiniteAllowance(uint256 funded, uint256 amount, uint256 approval)
        public
    {
        funded = bound(funded, 0, SUPPLY);
        amount = bound(amount, funded + 1, type(uint256).max - 1);
        approval = bound(approval, amount, type(uint256).max - 1);
        vm.prank(deployer);
        token.transfer(alice, funded);
        vm.prank(alice);
        token.approve(spender, approval);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funded, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approval, "failed transfer consumed approval");
        assertEq(token.balanceOf(deployer), SUPPLY - funded);
        assertEq(token.balanceOf(alice), funded);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidRecipientRestoresAllowance(uint256 approval, uint256 amount) public {
        amount = bound(amount, 0, approval < SUPPLY ? approval : SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approval);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), amount);
        assertEq(token.allowance(deployer, spender), approval);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DirectTransferPreservesBothPartiesApprovals(uint256 amount, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approval);
        vm.prank(alice);
        token.approve(spender, approval);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.allowance(deployer, spender), approval);
        assertEq(token.allowance(alice, spender), approval);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedSpendingMatchesSingleTransfer(uint256 approval, uint256 amount, uint256 firstPart)
        public
    {
        amount = bound(amount, 0, approval < SUPPLY ? approval : SUPPLY);
        firstPart = bound(firstPart, 0, amount);
        vm.prank(deployer);
        GoatPro singleTransferToken = new GoatPro();
        vm.startPrank(deployer);
        token.approve(spender, approval);
        singleTransferToken.approve(spender, approval);
        vm.stopPrank();

        vm.startPrank(spender);
        assertTrue(singleTransferToken.transferFrom(deployer, alice, amount));
        assertTrue(token.transferFrom(deployer, alice, firstPart));
        assertTrue(token.transferFrom(deployer, alice, amount - firstPart));
        vm.stopPrank();
        assertEq(token.balanceOf(deployer), singleTransferToken.balanceOf(deployer));
        assertEq(token.balanceOf(alice), singleTransferToken.balanceOf(alice));
        assertEq(token.allowance(deployer, spender), singleTransferToken.allowance(deployer, spender));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.allowance(deployer, spender), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
