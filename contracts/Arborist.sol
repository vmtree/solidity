// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/LinkTokenInterface.sol";
import "./VMTree.sol";

contract Arborist is Ownable {
    /**
     * This contract is the factory that deploys new VMTrees and the beacon that
     * the Chainlink DON listens to for triggering updates.
     */
    using Clones for address;

    event LinkCollected(
        address indexed collector,
        uint amount
    );

    // new tree deployed
    event VMTreeCloned(
        address tree,
        address controller,
        uint initialLinkDeposit,
        address indexed linkPayer
    );

    // tree ready for update
    event VMTreeSprouted(
        address tree
    );

    // tree was updated
    event VMTreeHarvested(
        address indexed tree,
        address indexed linkNode,
        address indexed linkPayer,
        uint linkPayment
    );

    // the vmTreeTemplate is deployed in the constructor of this contract
    address public vmTreeTemplate;
    // this is for rinkeby testnet only
    address public constant linkToken = 0x01BE23585060835E02B77ef475b0Cc51aA1e0709;

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
        uint expectedPayment;
        unchecked {
            expectedPayment = linkPayment * 10;
        }

        if (amount < expectedPayment) {
            revert TokenNeeded(expectedPayment);
        } else if (data.length != 32) {
            revert InvalidDataLength();
        } else if (msg.sender != linkToken) {
            revert OnlyLink();
        }

        address controller = abi.decode(data, (address));
        address tree = cloneAndPlant(controller);

        linkPayers[tree] = sender;
        uint linkBalance = linkPayerBalance[sender];

        unchecked {
            linkPayerBalance[sender] = linkBalance + amount;
        }

        emit VMTreeCloned(tree, controller, amount, sender);
    }

    // this function is called within `onTokenTransfer`. to deploy, use
    // `transferAndCall` on the LINK contract with `controller` as the data
    function cloneAndPlant(address controller)
        internal
        returns (address)
    {
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

        emit VMTreeSprouted(msg.sender);
    }

    // this function is called after an update to increment the node's balance
    // and to decrement the payer's balance
    function harvest(address linkNode)
        external
    {
        address linkPayer = linkPayers[msg.sender];
        uint payment = linkPayment;
        uint linkBalance = linkPayerBalance[linkPayer];

        // all descendents of vmTree will have nonzero linkPayer set
        if (linkPayer == address(0)) {
            revert OnlyDescendants();
        } else if (linkBalance < payment) {
            // chainlink node will avoid reverting tx
            revert InsufficientLinkBalance(linkPayer);
        }

        unchecked {
            linkPayerBalance[linkPayer] = linkBalance - payment;
            linkNodeBalance[linkNode] += payment;
        }

        emit VMTreeHarvested(msg.sender, linkNode, linkPayer, linkPayment);
    }

    function collectLinkNodeLink(address to) external {
        uint collectionAmount = linkNodeBalance[msg.sender];
        if (collectionAmount == 0) {
            revert InsufficientLinkBalance(msg.sender);
        }
        linkNodeBalance[msg.sender] = 0;

        LinkTokenInterface(linkToken).transfer(to, collectionAmount);
        emit LinkCollected(msg.sender, collectionAmount);
    }

    // warning: this function can prevent a VMTree from functioning if the
    // balance gets too low
    function collectLinkPayerLink(uint amount) external {
        uint linkBalance = linkPayerBalance[msg.sender];
        if (linkBalance < amount) {
            revert InsufficientLinkBalance(msg.sender);
        }
        unchecked {
            linkPayerBalance[msg.sender] = linkBalance - amount;
        }

        LinkTokenInterface(linkToken).transfer(msg.sender, amount);
        emit LinkCollected(msg.sender, amount);
    }

    // warning: anyone can topup a linkPayer's balance, but the linkPayer can
    // withdraw it (so they could potentially steal LINK tokens if someone else
    // tops up their account)
    function topUpLink(address linkPayer, uint amount) external {
        unchecked {
            linkPayerBalance[linkPayer] += amount;
        }

        if (!LinkTokenInterface(linkToken).transferFrom(
            msg.sender,
            address(this),
            amount
        )) revert TopUpFailed();
    }

    error InsufficientLinkBalance(address linkPayerOrCollector);
    error InvalidDataLength();
    error OnlyDescendants();
    error OnlyLink();
    error TokenNeeded(uint amount);
    error TopUpFailed();
}