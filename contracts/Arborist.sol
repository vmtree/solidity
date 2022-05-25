// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/ILinkToken.sol";
import "./VMTree.sol";

contract Arborist is Ownable {
    /**
     * This contract is the factory that deploys new VMTrees and the beacon that
     * the Chainlink DON listens to for triggering updates.
     */
    using Clones for address;

    // for frontend
    struct VMTreeData {
        string name;
        bool isActive;
        address contractAddress;
        address controller;
        address linkPayer;
    }

    // link payments and such
    event LinkCollected(
        address indexed source,
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

    // directrequest requires the OracleRequest event
    event OracleRequest(
        bytes32 indexed specId,
        address requester,
        bytes32 requestId,
        uint256 payment,
        address callbackAddr,
        bytes4 callbackFunctionId,
        uint256 cancelExpiration,
        uint256 dataVersion,
        bytes data
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
    // rinkeby testnet: 0x01BE23585060835E02B77ef475b0Cc51aA1e0709
    address public immutable linkToken;
    bytes32 public immutable specId;

    uint public linkPayment;
    mapping (address => address) public linkPayers;
    mapping (address => uint) public linkPayerBalance;
    mapping (address => uint) public linkNodeBalance;

    mapping (address => uint) public linkNodeIndex;
    address[] public linkNodes;
    uint public linkNodeQueue;

    mapping (address => uint) public vmtreeIndex;
    VMTreeData[] public vmtrees;

    constructor(uint _linkPayment, address _linkToken, bytes32 _specId) {
        linkPayment = _linkPayment;
        linkToken = _linkToken;
        specId = _specId;
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
        } else if (data.length < 96) {
            revert InvalidDataLength();
        } else if (msg.sender != linkToken) {
            revert OnlyLink();
        }

        // NOTE: hardhat failed to infer the reason for this reverting
        (address controller, string memory name) = abi.decode(
            data, 
            (address, string)
        );
        address tree = cloneAndPlant(controller);

        linkPayers[tree] = sender;
        uint linkBalance = linkPayerBalance[sender];

        uint newLinkPayerBalance;
        unchecked {
            newLinkPayerBalance = linkBalance + amount;
            linkPayerBalance[sender] = newLinkPayerBalance;
        }

        // do this for the frontend. ideally v2 indexes from log events?
        VMTreeData memory vmtree = VMTreeData({
            name: name,
            isActive: true,
            contractAddress: tree,
            controller: controller,
            linkPayer: sender
        });
        vmtreeIndex[tree] = vmtrees.length;
        vmtrees.push(vmtree);

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
    function sprout(uint nonce)
        external
    {
        // all descendents of vmTree will have nonzero linkPayer set
        address linkPayer = linkPayers[msg.sender];
        if (linkPayer == address(0)) {
            revert OnlyDescendants();
        }

        emit VMTreeSprouted(msg.sender);
        emit OracleRequest(
            specId,
            msg.sender,
            keccak256(abi.encodePacked(msg.sender, nonce)),
            linkPayment,
            msg.sender,
            bytes4(0),
            nonce,
            1,
            ""
        );
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

    // this function is called by the tree to make sure the payment will succeed
    function checkTreeBalance(address tree) external view returns (uint) {
        address linkPayer = linkPayers[tree];
        return linkPayerBalance[linkPayer];
    }

    function collectLinkNodeLink(address to) external {
        uint collectionAmount = linkNodeBalance[msg.sender];
        if (collectionAmount == 0) {
            revert InsufficientLinkBalance(msg.sender);
        }
        linkNodeBalance[msg.sender] = 0;

        ILinkToken(linkToken).transfer(to, collectionAmount);
        emit LinkCollected(address(this), msg.sender, collectionAmount);
    }

    // warning: this function can prevent a VMTree from functioning if the
    // balance gets too low
    function collectLinkPayerLink(address to, uint amount) external {
        uint linkBalance = linkPayerBalance[msg.sender];
        if (linkBalance < amount) {
            revert InsufficientLinkBalance(msg.sender);
        }
        unchecked {
            linkPayerBalance[msg.sender] = linkBalance - amount;
        }

        ILinkToken(linkToken).transfer(to, amount);
        emit LinkCollected(msg.sender, to, amount);
    }

    // warning: anyone can topup a linkPayer's balance, but the linkPayer can
    // withdraw it (so they could potentially steal LINK tokens if someone else
    // tops up their account)
    function topUpLink(address linkPayer, uint amount) external {
        unchecked {
            linkPayerBalance[linkPayer] += amount;
        }

        if (!ILinkToken(linkToken).transferFrom(
            msg.sender,
            address(this),
            amount
        )) revert TopUpFailed();

        emit LinkCollected(msg.sender, linkPayer, amount);
    }

    // solidity generates a public function, but it's an indexed array function.
    // this returns all of the trees in the array in a single call
    function getVMTrees() external view returns (uint, VMTreeData[] memory) {
        return (vmtrees.length, vmtrees);
    }

    error InsufficientLinkBalance(address linkPayerOrCollector);
    error InvalidDataLength();
    error OnlyDescendants();
    error OnlyLink();
    error TokenNeeded(uint amount);
    error TopUpFailed();
}