// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./VMTree.sol";

contract Arborist is Ownable {
    using Clones for address;
    /**
     * This contract is the factory and beacon that the Chainlink node
     * listens to.
     */

    // new tree deployed
    event VMTreeCloned(
        address tree,
        address controller,
        uint initialLinkDeposit,
        address indexed linkPayer
    );

    // tree ready for update
    event VMTreeSprouted(address indexed tree, address linkPayer);

    // tree was updated
    event VMTreePruned(
        address indexed tree,
        address indexed linkNode,
        address indexed linkPayer,
        uint linkPayment
    );

    // the vmTreeTemplate is deployed in the constructor of this contract
    address public vmTreeTemplate;
    // this is for rinkeby testnet only
    address public constant linkToken = 0x01BE23585060835E02B77ef475b0Cc51aA1e0709;
    // can be adjusted by owner
    uint public linkPayment;

    mapping (address => address) public linkPayers;
    mapping (address => uint) public linkPayerBalance;
    mapping (address => uint) public linkNodeBalance;

    constructor(uint _linkPayment) {
        linkPayment = _linkPayment;
        vmTreeTemplate = address(new VMTree());
    }

    // whoever calls `transferAndCall` on the LINK token contract is the sender
    function onTokenTransfer(
        address sender,
        uint amount,
        bytes calldata data
    )
        external
    {
        if (msg.sender != linkToken) {
            revert OnlyLink();
        }
        uint expectedPayment;
        unchecked {
            expectedPayment = linkPayment * 10;
        }

        if (amount < expectedPayment) {
            revert TokenNeeded(expectedPayment);
        } else if (data.length != 32) {
            revert InvalidDataLength();
        }

        address controller = abi.decode(data, (address));
        (bool success, bytes memory returnData) = address(this).delegatecall(
            abi.encodeWithSelector(this.clone.selector, controller, sender)
        );

        if (!success) {
            revert CloneFailed();
        } else {
            address tree = abi.decode(returnData, (address));
            linkPayers[tree] = sender;

            uint linkBalance = linkPayerBalance[sender];
            unchecked {
                linkPayerBalance[sender] = linkBalance + amount;
            }

            emit VMTreeCloned(tree, controller, amount, sender);
        }
    }

    // this function is called within `onTokenTransfer`. to deploy, use
    // `transferAndCall` on the LINK contract
    function clone(address controller)
        external
        returns
        (address)
    {
        if (msg.sender != linkToken) {
            revert OnlyLink();
        }
        address sapling = vmTreeTemplate.clone();
        VMTree(sapling).plant(address(this), controller);
        return sapling;
    }

    // this function alerts the chainlink don that a tree is ready to be updated
    function sprout()
        external
    {
        // all descendents of vmTree will have nonzero linkPayer set
        address linkPayer = linkPayers[msg.sender];
        if (linkPayer == address(0)) {
            revert OnlyDescendants();
        }

        emit VMTreeSprouted(msg.sender, linkPayer);
    }

    function harvest(address linkNode)
        external
    {
        // all descendents of vmTree will have nonzero linkPayer set
        address linkPayer = linkPayers[msg.sender];
        if (linkPayer == address(0)) {
            revert OnlyDescendants();
        }

        uint payment = linkPayment;
        uint linkBalance = linkPayerBalance[linkPayer];
        if (linkBalance < payment) {
            revert InsufficientLinkBalance(linkPayer);
        }

        unchecked {
            linkPayerBalance[linkPayer] = linkBalance - payment;
            linkNodeBalance[linkNode] += payment;
        }

        emit VMTreePruned(msg.sender, linkNode, linkPayer, linkPayment);
    }

    error CloneFailed();
    error InsufficientLinkBalance(address linkPayer);
    error InvalidDataLength();
    error OnlyLink();
    error OnlyDescendants();
    error TokenNeeded(uint amount);
}