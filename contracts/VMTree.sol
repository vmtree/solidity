// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./interfaces/IArborist.sol";
import "./verifiers/MassUpdateVerifier.sol";

contract VMTree is MassUpdateVerifier {

    error InsufficientLeaves();
    error InsufficientLinkBalance(address linkPayerOrCollector);
    error InvalidUpdateProof();
    error InvalidMassUpdateProof();
    error InvalidMsgSender();
    error OnlyController();
    error TreeAlreadyPlanted();
    error TreeIsFull();
    error ZeroAddress();

    event LeafCommitted(uint leaf, uint index);
    event TreeUpdated(uint previousIndex, uint nextIndex);

    uint private constant LEVELS = 20;
    uint private constant BATCH_SIZE = 16;
    uint private constant OFFSET_FILLED_SUBTREES = 2;
    uint private constant OFFSET_NEW_SUBTREES = OFFSET_FILLED_SUBTREES + LEVELS;
    uint private constant OFFSET_LEAVES = OFFSET_NEW_SUBTREES + LEVELS;
    uint private constant N_PUBLIC_SIGNALS = OFFSET_LEAVES + BATCH_SIZE;
    uint private constant TREE_CAPACITY = 1 << LEVELS;
    address private arborist;
    address private controller;
    mapping(uint => uint) private commitments;
    uint private nextIndex;
    uint[LEVELS] private filledSubtrees;

    uint public latestIndex;
    uint public currentRoot;

    function plant(address _arborist, address _controller) external {
        if (_arborist == address(0) || _controller == address(0)) {
            revert ZeroAddress();
        } else if (arborist != address(0)) {
            revert TreeAlreadyPlanted();
        }
        arborist = _arborist;
        controller = _controller;
        uint[32] memory zeros = [
            0x1afaac8e3a7748c3f03aabbaf80c9593fb24ab3f9cad18f143a9dcc17849d35c,
            0x141995d79e6b4abeabebc2901a93834d49004039b15f5848f55f9873beac93c3,
            0x073a152acc83c70e196e2f1adfeef593c16a6c4d163b97728e6a7278cc801348,
            0x05f4bce4568668f276842d88ceea3166a397dc7b85aef67ee066c6284f99b317,
            0x212ebe78fb63723efcc8bd57dc4eeeecf5fea1b9d42951a767d6e32c3e331f50,
            0x15e356f8c09f0500a4282aca55c36649d3d20178ac95523978836dc51e85aed2,
            0x1cc1329d8a531550cd7e46bc3bf7f39a8f347e656858bae8a01a155d6abf0307,
            0x14f60777b76dd766c2605c8a40c90261e32f46f7fee198380aff7ef7ddf08013,
            0x114fb6534ddba8b53521f3f415817e483b899e263c693e4fc35760492c8fb6a0,
            0x052913002a39146ab08c32a1b732e8073a48a53940b2df8de3c1ca07758bd2b2,
            0x14c3f02c584317db693db7df51e7739d17824aaa90f9f37778ec6ca35ff9b633,
            0x2d30e3b5645cee0f6e597cd11753bf60f4cea529af9d8ae5104cf296c9bb0201,
            0x013c71504dc68143f920f6f26a2ce460b1c79c1e7ed6563447329f0302257035,
            0x013d11110eccb7fa8634efa4053b4bb064330c0fa4651849c890f72fddd2f78d,
            0x0c2a7d8ebf453e616f1dd48a065cd8a3ff8b37901e81460513c5d263bf6e85fe,
            0x15876ac2e5eaf8e6b83405357331d4852226402a9b304c1bf6b5382518149b61,
            0x0b697a840076e05b8c77d8d3e79ceee525dfcbd559aeebe0eab108a3ce8decec,
            0x0de34184e19231bb8aaa3b846b8495f2443f5d652055380a6df5c4855f081bc7,
            0x1f1dec293fe89561513bbe1ba0d09b170d11fed8c3440f1bcf0e00beaad7279b,
            0x1cf81850d57c910a1b49c3fcf035376148a99540a3a70f1062bc67c752f81e37,
            0x263b0af2cc00ae97de1a98c1db4070767b275313aab28d4ad87b7b293ce794ee,
            0x17af95bb3f1d0929655e1cb1565538b4a1714ba5f03079d3e286fd19cf3479ef,
            0x05873d44e99d000fa3add2efa8f3a317ebcfe72b2dd66348e0398f61c27d5f04,
            0x26ad3b05001810ac5213459bbea47eae15705195bd3936181fecff21416e6a9c,
            0x1ee7c900e6caea171bc1f078171440144a9fbcfad54abf2973396a9943f47d88,
            0x056b1f9418e15507f2b6d39cc77522e73816ce56c98cb4bac50db479ca64c727,
            0x0920e57ffaa87b220a611948ae09955bf3dcc3bc1526e8f4bcd76aa5cdc2cebd,
            0x2a18f9acac248e42ff903a32dcb15620b78f3b047038728ac0d295c609ce9b6a,
            0x28d07e1e14dfc797e526f988165e5fcfc619cc1119841e7729b09bcbc236d0e9,
            0x08982b5df134bc06316c283b47c6525c089a6617e47690a9094b00e74179ecd4,
            0x2ad48d1ed7f4fc3cb40566a160b4480825d57e1585a3271c82b5a9a270fe7303,
            0x1fe56fc51e4735b2118a291e3771f5314ae4f633758ffede033aac4d636d2de5
        ];
        for (uint i; i < LEVELS;) {
            filledSubtrees[i] = zeros[i];
            ++i;
        }
        currentRoot = zeros[LEVELS];
    }

    function getFilledSubtrees() public view returns (uint[20] memory) {
        return filledSubtrees;
    }

    function commit(uint leaf) public returns (uint) {
        uint i = latestIndex;
        if (i == TREE_CAPACITY) {
            revert TreeIsFull();
        } else if (msg.sender != controller) {
            revert OnlyController();
        }
        commitments[i] = leaf;
        uint newLatestIndex;
        unchecked {
            newLatestIndex = i + 1;
        }
        latestIndex = newLatestIndex;
        uint startIndex = nextIndex;
        if ((newLatestIndex - startIndex) >= BATCH_SIZE) {
            IArborist(arborist).sprout(startIndex);
        }
        emit LeafCommitted(leaf, i);
        return i;
    }

    function checkMassUpdate()
        external
        view
        returns (uint[BATCH_SIZE] memory, uint[LEVELS] memory, uint)
    {
        uint startIndex = nextIndex;
        uint latest = latestIndex;
        unchecked {
            if ((latest - startIndex) < BATCH_SIZE)
                revert InsufficientLeaves();
        }
        uint[BATCH_SIZE] memory leaves;
        for (uint i; i < BATCH_SIZE;) {
            unchecked {
                leaves[i] = commitments[startIndex + i];
                ++i;
            }
        }
        uint linkBalance = IArborist(arborist).checkTreeBalance(address(this));
        if (linkBalance < IArborist(arborist).linkPayment()) {
            revert InsufficientLinkBalance(address(this));
        }
        return (leaves, filledSubtrees, startIndex);
    }

    function performMassUpdate(
        uint newRoot,
        uint[LEVELS] calldata newSubtrees,
        uint[8] calldata proof
    )
        public
        returns (uint finalIndex)
    {
        uint startIndex = nextIndex;
        unchecked {
            if ((latestIndex - startIndex) < BATCH_SIZE)
                revert InsufficientLeaves();
            finalIndex = startIndex + BATCH_SIZE;
        }
        uint[N_PUBLIC_SIGNALS] memory publicSignals;
        publicSignals[0] = newRoot;
        publicSignals[1] = startIndex;
        for (uint i; i < LEVELS;) {
            unchecked {
                publicSignals[i + OFFSET_FILLED_SUBTREES] = filledSubtrees[i];
                publicSignals[i + OFFSET_NEW_SUBTREES] = newSubtrees[i];
                ++i;
            }
        }
        for (uint i; i < BATCH_SIZE;) {
            unchecked {
                uint c = i + startIndex;
                publicSignals[i + OFFSET_LEAVES] = commitments[c];
                delete commitments[c];
                ++i;
            }
        }
        if (!_verifyMassUpdateProof(
            proof,
            publicSignals
        ))
            revert InvalidMassUpdateProof();
        for (uint i; i < LEVELS;) {
            unchecked {
                if (publicSignals[i + OFFSET_FILLED_SUBTREES] != newSubtrees[i]) {
                    filledSubtrees[i] = newSubtrees[i];
                }
                ++i;
            }
        }
        currentRoot = newRoot;
        nextIndex = finalIndex;
        IArborist(arborist).harvest(msg.sender);
    }
}