// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions


// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "forge-std/console.sol";

/**
 * @title Sample Raffle contreact
 * @author Yoan Enchev
 * @notice Creating a sample raffle
 * @dev Uses chainlink VRF v2
 */
contract Raffle is VRFConsumerBaseV2{ 

    error Raffle__NotEnoughETHSpent();
    error Raffle_TransferFailed();
    error Raffle_Not_Open();
    error Raffle_UpKeepNotNeeded(
        uint256 currentBalance,
        uint256 numOfPlayers,
        uint256 raffleState
    );

    /** Type Declarations */
    enum RaffleState {
        OPEN, CALCULATING
    }

    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUMBER_OF_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval; // Duration of lottery in seconds.
    VRFCoordinatorV2Interface private immutable i_vtfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionID;
    uint32 private immutable i_callbackGasLimit;


    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;

    RaffleState s_raffleState = RaffleState.OPEN;


    constructor(uint256 enteranceFee, uint256 interval, address vrfCoordinator, bytes32 gasLane, uint64 subscriptionID, uint32 callbackGasLimit) 
        VRFConsumerBaseV2(vrfCoordinator) {


        i_entranceFee = enteranceFee;
        i_interval = interval;
        i_vtfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionID = subscriptionID;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughETHSpent();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_Not_Open();
        }

        s_players.push(payable(msg.sender));

        emit EnteredRaffle(msg.sender);
    }

    /*
     * @dev When winner should be picked
     * @param null 
     * @return upkeepNeeded 
     */
    function checkUpkeep(bytes memory /* checkData */)
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool timeHasPased = (block.timestamp - s_lastTimeStamp > i_interval);
        bool isOpened = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;

        upkeepNeeded = (timeHasPased && isOpened && hasBalance && hasPlayers);

        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /** performData */) external {

        (bool upKeepNeeded, ) = checkUpkeep("");

        // Check if enough time has passed
        if (!upKeepNeeded) {
            revert Raffle_UpKeepNotNeeded(

                // Debug info:
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;

        // Pick a random number
        uint256 requestId = i_vtfCoordinator.requestRandomWords(
            i_gasLane, // Gas lane - specify to not spend too many gas
            i_subscriptionID, // your subscription id
            REQUEST_CONFIRMATIONS, // number of block confirmations
            i_callbackGasLimit, // to make not over spent gas
            NUMBER_OF_WORDS // how many random numbers we want returned
        );

        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestID*/,
        uint256[] memory randomWords
    ) internal override {

        uint256 indexOfWinner = randomWords[0] % s_players.length;

        address payable winner = s_players[indexOfWinner];
        
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;

        s_players = new address payable[](0);

        emit PickedWinner(winner);

        (bool success,) = s_recentWinner.call{value: address(this).balance}("");
        s_lastTimeStamp = block.timestamp;

        if (!success) {
            revert Raffle_TransferFailed();
        }
    }

    /**
     * Getter functions
     */
    function getEnteranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}