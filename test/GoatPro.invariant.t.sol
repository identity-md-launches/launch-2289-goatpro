// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {GoatPro} from "../src/GoatPro.sol";

/// @dev All test funds stay among four actors, so the model accounts for the entire supply.
contract GoatProHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    GoatPro private immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(GoatPro token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 valueSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 value = bound(valueSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, value));
        expectedBalance[from] -= value;
        expectedBalance[to] += value;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 valueSeed, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Finite approvals can exceed the entire supply; only uint256.max is unlimited.
        uint256 value = unlimited ? type(uint256).max : bound(valueSeed, 0, type(uint256).max - 1);
        vm.prank(owner);
        assertTrue(token.approve(spender, value));
        expectedAllowance[owner][spender] = value;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 valueSeed, bool exceedLimit)
        external
    {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 limit = approved < balance ? approved : balance;
        uint256 value = exceedLimit ? limit + 1 : bound(valueSeed, 0, limit);

        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(IERC20.transferFrom, (from, to, value)));
        if (exceedLimit) {
            assertFalse(success, "invalid transferFrom succeeded");
            if (value > approved) {
                assertEq(
                    result,
                    abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, value),
                    "wrong allowance failure"
                );
            } else {
                assertEq(
                    result,
                    abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, value),
                    "wrong balance failure"
                );
            }
            // No model updates: the invariant also checks that a revert preserved all state.
            return;
        }
        assertTrue(success, "valid transferFrom reverted");
        assertTrue(abi.decode(result, (bool)));
        expectedBalance[from] -= value;
        expectedBalance[to] += value;
        if (approved != type(uint256).max) {
            expectedAllowance[from][spender] = approved - value;
        }
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 valueSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 value = bound(valueSeed, balance + 1, type(uint256).max);
        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(IERC20.transfer, (to, value)));
        assertFalse(success, "over-balance transfer succeeded");
        assertEq(result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, value));
        // Leave the model unchanged so the invariant verifies rollback for every actor.
    }

    function transferToZero(uint256 fromSeed, uint256 spenderSeed, uint256 valueSeed, bool delegated) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 limit = expectedBalance[from];
        if (delegated && expectedAllowance[from][spender] < limit) {
            limit = expectedAllowance[from][spender];
        }
        uint256 value = bound(valueSeed, 0, limit);
        bytes memory data = delegated
            ? abi.encodeCall(IERC20.transferFrom, (from, address(0), value))
            : abi.encodeCall(IERC20.transfer, (address(0), value));
        vm.prank(delegated ? spender : from);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "transfer to zero succeeded");
        assertEq(result, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 value) external {
        address owner = actors[ownerSeed % actors.length];
        vm.prank(owner);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(IERC20.approve, (address(0), value)));
        assertFalse(success, "approval to zero succeeded");
        assertEq(result, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 valueSeed) external {
        uint256 fromIndex = fromSeed % actors.length;
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length];
        uint256 fromBalance = expectedBalance[from];
        uint256 toBalance = expectedBalance[to];
        uint256 value = fromBalance == 0 ? 0 : bound(valueSeed, 1, fromBalance);

        vm.prank(from);
        assertTrue(token.transfer(to, value));
        assertEq(token.balanceOf(from), fromBalance - value);
        assertEq(token.balanceOf(to), toBalance + value);
        vm.prank(to);
        assertTrue(token.transfer(from, value));
        assertEq(token.balanceOf(from), fromBalance, "round trip lost or created tokens");
        assertEq(token.balanceOf(to), toBalance, "round trip changed the counterparty's funds");
        // Net effect is zero; every allowance must also still match the unchanged model.
    }
}

contract GoatProInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    GoatPro private token;
    GoatProHandler private handler;
    address[4] private actors;

    function setUp() public {
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        token = new GoatPro();
        handler = new GoatProHandler(token, actors);
        token.transfer(actors[0], SUPPLY);

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = GoatProHandler.transfer.selector;
        selectors[1] = GoatProHandler.approve.selector;
        selectors[2] = GoatProHandler.revoke.selector;
        selectors[3] = GoatProHandler.transferFrom.selector;
        selectors[4] = GoatProHandler.transferOverBalance.selector;
        selectors[5] = GoatProHandler.transferToZero.selector;
        selectors[6] = GoatProHandler.approveZeroSpender.selector;
        selectors[7] = GoatProHandler.roundTrip.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 128
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SupplyBalancesAndAllowancesMatchModel() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.name(), "GoatPro");
        assertEq(token.symbol(), "GPRO");
        assertEq(token.decimals(), 18);
        uint256 summedBalances;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            summedBalances += balance;
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
        assertEq(summedBalances, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    /// @dev Each random sequence must leave every holder able to move their entire balance.
    function afterInvariant() public {
        for (uint256 i = 1; i < actors.length; ++i) {
            uint256 balance = handler.expectedBalance(actors[i]);
            vm.prank(actors[i]);
            assertTrue(token.transfer(actors[0], balance), "holder cannot transfer their full balance");
            assertEq(token.balanceOf(actors[i]), 0);
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY, "consolidation lost tokens");
        assertEq(token.totalSupply(), SUPPLY);
    }
}
