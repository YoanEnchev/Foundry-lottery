// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {

    /* Events */
    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrdCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();

        (
            entranceFee,
            interval,
            vrdCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,
            deployerKey
        ) = helperConfig.activeNetworkConfig();

        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    ///////////////////////////
    // enterEaffle           //
    ///////////////////////////
    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);

        vm.expectRevert(Raffle.Raffle__NotEnoughETHSpent.selector);

        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);

        raffle.enterRaffle{value: entranceFee}();

        address playerRecorded = raffle.getPlayer(0);

        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrace() public {
        vm.prank(PLAYER);
        
        // Both lines tell what should we expect to emit:
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);

        // Line which should emit the event:
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);

        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1); // Simulate enough time passed 
        vm.roll(block.number + 1); // Simulate more blocks we added

        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle_Not_Open.selector);

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }


    ///////////////////////////
    // checkUpKeep           //
    ///////////////////////////

    //  More like no players
    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        // Enough time gas passed
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfRaffleNotOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfENoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsTrueWhenParametersAreGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(upkeepNeeded);
    }


    ///////////////////////////
    // performUpkeep         //
    ///////////////////////////
    function testPerformUpKeepCanOnlyRunIfCheckUpKeepIsTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Will not throw error if it doesn't revert:
        raffle.performUpkeep("");
    }

    function testPerformUpKeepReventsIfCheckUpKeepIsFalse() public {
        
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;

        vm.expectRevert(abi.encodeWithSelector(Raffle.Raffle_UpKeepNotNeeded.selector, currentBalance, numPlayers, raffleState));
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        _;
    }

    function testPerformUpKeepUpdateRaffleStateAndEmitsRequestId() public raffleEnteredAndTimePassed {
        vm.recordLogs(); // Save into logs emited events

        raffle.performUpkeep("");

        Vm.Log[] memory entries = vm.getRecordedLogs();


        // requestId refers to the parameter of RequestedRaffleWinner
        bytes32 requestID = entries[1].topics[1]; //topis[1] refers to the first parameter

        Raffle.RaffleState rState = raffle.getRaffleState();

        assert(uint256(requestID) > 0);
        assert(uint256(rState) == 1);
    }


    ////////////////////////////////
    // fulfillRandomWords         //
    ////////////////////////////////
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpKeep(uint256 randomRequestID) public raffleEnteredAndTimePassed {
        vm.expectRevert("nonexistent request");

        VRFCoordinatorV2Mock(vrdCoordinator).fulfillRandomWords(randomRequestID, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEnteredAndTimePassed {
        uint256 addionalEntrants = 5;
        uint256 startingIndex = 1;


        // A bunch of player entered the lottery
        for (uint256 i = startingIndex; i < startingIndex + addionalEntrants; i++) {
            address player = address(uint160(i)); // It should be the same as makeAddr.
            hoax(player, STARTING_USER_BALANCE);


            raffle.enterRaffle{value: entranceFee}();
        }

        // Pretend to be chainlink vrf to get random number & pick winner
        vm.recordLogs(); // Save into logs emited events
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestID = entries[1].topics[1];
    
        uint256 prevousTimeStamp = raffle.getLastTimeStamp();

        VRFCoordinatorV2Mock(vrdCoordinator).fulfillRandomWords(uint256(requestID), address(raffle));

        // Assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLengthOfPlayers() == 0);
        assert(prevousTimeStamp < raffle.getLastTimeStamp());

        uint256 prize = entranceFee * addionalEntrants;

        assert(raffle.getRecentWinner().balance == STARTING_USER_BALANCE + prize);
    }
}