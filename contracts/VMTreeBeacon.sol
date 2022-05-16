// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;


contract VMTreeBeacon {

    /**
     * @note This contract is the central beacon that the Chainlink node
     * listens to. It's mainly for emitting events, access control is to
     * prevent malicious signalling (e.g. pointing the node to a contract that
     * isn't a VMTree).
     */

    error InvalidMsgSender();

    event VMTreePlanted(address vmt);
    event VMTreeSprouted(address vmt);
    event VMTreeHarvested(address vmt, address indexed linkNode);

    address owner;
    mapping (address => bool) public isValidTree;

    constructor() {
        owner = msg.sender;
    }

    function plant(address tree) external onlyOwner {
        isValidTree[tree] = true;
        emit VMTreePlanted(tree);
    }

    function sprout() external onlyVMT {
        emit VMTreeSprouted(msg.sender);
    }

    function harvest(address linkNode) external onlyVMT {
        emit VMTreeHarvested(msg.sender, linkNode);
    }

    modifier onlyOwner() {
        if (msg.sender != owner)
            revert InvalidMsgSender();
        _;
    }

    modifier onlyVMT() {
        if (!isValidTree[msg.sender])
            revert InvalidMsgSender();
        _;
    }
}