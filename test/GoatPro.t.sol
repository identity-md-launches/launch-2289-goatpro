// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {GoatPro} from "../src/GoatPro.sol";

/// @dev Local deployment fixture, never part of the launch.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (GoatPro) {
        return new GoatPro{salt: salt}();
    }

    function send(GoatPro token, address to, uint256 value) external {
        require(token.transfer(to, value), "transfer failed");
    }
}

contract GoatProTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    GoatPro private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        vm.prank(deployer);
        token = new GoatPro();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "GoatPro");
        assertEq(token.symbol(), "GPRO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        vm.prank(deployer);
        GoatPro fresh = new GoatPro();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(deployer))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_Create2MintsToFactoryRatherThanItsCaller() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        vm.prank(alice);
        GoatPro launched = factory.deploy(keccak256("goatpro test deployment"));
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_FactoryDistributionClaimsAndPoolTransfersAreExact() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        GoatPro launched = factory.deploy(keccak256("goatpro distribution test"));
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool manager transfer fixture");
        uint256 swarm = SUPPLY / 10;
        uint256 liquidity = SUPPLY * 8 / 10;

        factory.send(launched, distributor, swarm);
        factory.send(launched, pool, liquidity);
        factory.send(launched, alice, SUPPLY - swarm - liquidity);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(pool), liquidity);
        assertEq(launched.balanceOf(alice), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(launched.transfer(bob, swarm));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(bob), swarm);

        // Exercise exact token delivery in both pool directions; no AMM is simulated.
        vm.prank(pool);
        assertTrue(launched.transfer(spender, 100 ether));
        assertEq(launched.balanceOf(spender), 100 ether);
        assertEq(launched.balanceOf(pool), liquidity - 100 ether);
        vm.prank(spender);
        assertTrue(launched.transfer(pool, 100 ether));
        assertEq(launched.balanceOf(pool), liquidity);
        assertEq(launched.balanceOf(spender), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, 123 ether);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireBalanceCanBeTransferred() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountSucceedsAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferRejectsZeroRecipientIncludingZeroAmount() public {
        vm.startPrank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.stopPrank();
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferRejectsInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(deployer);
        token.transfer(deployer, SUPPLY + 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_ApproveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(deployer, spender, 50 ether);
        vm.startPrank(deployer);
        assertTrue(token.approve(spender, 50 ether));
        assertEq(token.allowance(deployer, spender), 50 ether);
        assertTrue(token.approve(spender, 20 ether));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 20 ether);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_ApproveRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function test_TransferFromSpendsAllowanceAndEmitsTransfer() public {
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 40 ether));
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 40 ether);
        assertEq(token.allowance(deployer, spender), 60 ether);

        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 60 ether));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(bob), 60 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        vm.prank(deployer);
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, 10 ether));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_UnlimitedAllowanceIsNotDecreased() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1 ether));
        assertTrue(token.transferFrom(deployer, bob, 2 ether));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 2 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 3 ether);
    }

    function test_RevokedAllowanceCannotBeSpent() public {
        vm.startPrank(deployer);
        token.approve(spender, type(uint256).max);
        token.approve(spender, 0);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_TransferFromRejectsUnapprovedCaller() public {
        vm.prank(deployer);
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, spender), 10 ether);
    }

    function test_TransferFromRejectsInsufficientAllowanceAtomically() public {
        vm.prank(deployer);
        token.approve(spender, 4 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 4 ether, 5 ether)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, 5 ether);
        assertEq(token.allowance(deployer, spender), 4 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferFromRejectsInsufficientBalanceAndRestoresAllowance() public {
        vm.prank(alice);
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1 ether);
        assertEq(token.allowance(alice, spender), 100 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromRejectsZeroRecipientAndRestoresAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 1 ether);
        assertEq(token.allowance(deployer, spender), 100 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_DeployerCannotSpendHolderFundsWithoutApproval() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_NoMintBurnOrAdministrativeEntryPoints() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        bytes[] memory attempts = new bytes[](13);
        attempts[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        attempts[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        attempts[2] = abi.encodeWithSignature("burn(uint256)", 1);
        attempts[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        attempts[4] = abi.encodeWithSignature("pause()");
        attempts[5] = abi.encodeWithSignature("blacklist(address)", alice);
        attempts[6] = abi.encodeWithSignature("freeze(address)", alice);
        attempts[7] = abi.encodeWithSignature("seize(address)", alice);
        attempts[8] = abi.encodeWithSignature("transferOwnership(address)", bob);
        attempts[9] = abi.encodeWithSignature("upgradeTo(address)", bob);
        attempts[10] = abi.encodeWithSignature("initialize(address)", bob);
        attempts[11] = abi.encodeWithSignature("setMinter(address)", bob);
        attempts[12] = abi.encodeWithSignature("owner()");

        for (uint256 i; i < attempts.length; ++i) {
            vm.prank(deployer);
            (bool deployerSuccess,) = address(token).call(attempts[i]);
            assertFalse(deployerSuccess);
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(attempts[i]);
            assertFalse(strangerSuccess);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function testFuzz_TransfersConserveSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovedTransferSpendsOnlyRequestedAmount(uint256 approval, uint256 amount) public {
        approval = bound(approval, 0, SUPPLY);
        amount = bound(amount, 0, approval);
        vm.prank(deployer);
        token.approve(spender, approval);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, amount));
        assertEq(token.allowance(deployer, spender), approval - amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverBalanceTransferReverts(uint256 excess) public {
        excess = bound(excess, 1, type(uint256).max - SUPPLY);
        uint256 amount = SUPPLY + excess;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        vm.prank(deployer);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverAllowanceTransferReverts(uint256 approval, uint256 excess) public {
        approval = bound(approval, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - approval);
        uint256 amount = approval + excess;
        vm.prank(deployer);
        token.approve(spender, approval);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, amount)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, amount);
        assertEq(token.allowance(deployer, spender), approval);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
