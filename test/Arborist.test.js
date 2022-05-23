const { ethers } = require('hardhat');
const { expect } = require('chai');
const { deploy } = require('../scripts/hardhat.utils.js');
const {
    calculateSubtrees,
    calculateUpdateProof,
    calculateMassUpdateProof,
    mimcSponge,
    utils,
    verifyProof
} = require('vmtjs');

const updateVerifier = require('../circuits/updateVerifier.json');
const massUpdateVerifier = require('../circuits/massUpdateVerifier.json');

const {
    unsafeRandomLeaves,
    toVmtUpdateSolidityInput,
    toVmtMassUpdateSolidityInput,
} = utils;

function hexPadLeft(h) {
    return '0x' + h.slice(2).padStart(64, '0');
}

describe('[START] - Arborist.test.js', function() {
    before(async () => {
        const signers = await ethers.getSigners();
        this.sergey = signers[0];
        this.linkPayer = signers[1];
        this.linkNode = signers[2];
        this.controller = signers[4];
        this.linkPayment = ethers.utils.parseUnits('0.1');

        this.leaves = unsafeRandomLeaves(11).map(bn => bn.toString());

        this.startSubtrees = calculateSubtrees(
            mimcSponge,
            20,
            0,
            []
        );
        this.singleEndSubtrees = calculateSubtrees(
            mimcSponge,
            20,
            0,
            [this.leaves[0]]
        );
        this.endSubtrees = calculateSubtrees(
            mimcSponge,
            20,
            0,
            this.leaves
        );

        // deploy contracts
        this.linkToken = await deploy("LinkToken");
        this.arborist = await deploy(
            "Arborist",
            [this.linkPayment, this.linkToken.address]
        );
    });

    it('linkPayer balance should be 10 * linkPayment', async () => {
        await this.linkToken.transfer(
            this.linkPayer.address, 
            this.linkPayment.mul(10)
        );

        expect(await this.linkToken.balanceOf(this.linkPayer.address))
            .to.be.equal(this.linkPayment.mul(10));       
    });

    it('should deploy a vmtree using LINKs transferAndCall', async () => {
        await this.linkToken.connect(this.linkPayer).transferAndCall(
            this.arborist.address,
            this.linkPayment.mul(10),
            hexPadLeft(this.controller.address)
        );
        const [ log ] = await this.arborist.queryFilter('VMTreeCloned');

        const vmTreeFactory = await ethers.getContractFactory('VMTree');
        this.vmtree = new ethers.Contract(
            log.args.tree, vmTreeFactory.interface, this.controller
        );
    });

    it('should deposit 9 leaves into the tree', async () => {
        for (let i = 0; i < 9; i++) {
            await this.vmtree.commit(this.leaves[i]);
        }
    });

    it('should emit `VMTSprouted` on 10th deposit', async () => {
        await expect(this.vmtree.commit(this.leaves[9])).to.emit(
            this.arborist, 'VMTreeSprouted'
        ).withArgs(this.vmtree.address);
    });

    it('should generate a zero knowledge proof for a single deposit', async () => {
        console.time('update proof');
        this.updateProof = await calculateUpdateProof(
            "./circuits/update.wasm",
            "./circuits/update.zkey",
            0,
            this.leaves[0],
            this.startSubtrees,
            this.singleEndSubtrees
        );
        console.timeEnd('update proof');
        const result = await verifyProof(
            updateVerifier,
            this.updateProof.publicSignals,
            this.updateProof.proof
        );
        expect(result).to.be.true;
    });

    it('should update the VMTree for a single deposit', async () => {
        const { proof, publicSignals } = this.updateProof;
        const { p, newSubtrees } = toVmtUpdateSolidityInput(
            proof,
            publicSignals
        );

        const verifiableStartSubtrees = await this.vmtree.getFilledSubtrees();
        verifiableStartSubtrees.forEach((subtree, i) => {
            expect(subtree).to.be.equal(this.startSubtrees[i]);
        });
        await this.vmtree.connect(this.linkNode).update(p, newSubtrees);

        verifiableSingleEndSubtrees = await this.vmtree.getFilledSubtrees();
        verifiableSingleEndSubtrees.forEach((subtree, i) => {
            expect(subtree).to.be.equal(this.singleEndSubtrees[i]);
        });
    });

    it('should emit `VMTSprouted` again, on 11th deposit', async () => {
        await expect(this.vmtree.commit(this.leaves[10])).to.emit(
            this.arborist, 'VMTreeSprouted'
        ).withArgs(this.vmtree.address);
    });

    it('should generate a zero knowledge proof for 10 leaves', async() => {
        const [
            leaves,
            filledSubtrees,
            startIndex
        ] = await this.vmtree.checkMassUpdate();

        const endSubtrees = calculateSubtrees(
            mimcSponge,
            20,
            Number(startIndex),
            leaves,
            filledSubtrees
        );

        console.time('mass update proof');
        this.massUpdateProof = await calculateMassUpdateProof(
            "./circuits/massUpdate.wasm",
            "./circuits/massUpdate.zkey",
            startIndex,
            leaves,
            filledSubtrees,
            endSubtrees
        );
        console.timeEnd('mass update proof');
        const result = await verifyProof(
            massUpdateVerifier,
            this.massUpdateProof.publicSignals,
            this.massUpdateProof.proof
        );
        expect(result).to.be.true;
    });

    it('should have correct link balances before performMassUpdate', async () => {
        expect(await this.arborist.linkPayerBalance(this.linkPayer.address))
            .to.be.equal(this.linkPayment.mul(10));

        expect(await this.arborist.linkNodeBalance(this.linkNode.address))
            .to.be.equal(0);
    });

    it('should update the VMTree for 10 deposits', async () => {
        const { proof, publicSignals } = this.massUpdateProof;
        const { p, newSubtrees } = toVmtMassUpdateSolidityInput(
            proof,
            publicSignals
        );

        await expect(this.vmtree.connect(this.linkNode).performMassUpdate(
            p,
            newSubtrees
        )).to.emit(this.arborist, 'VMTreeHarvested').withArgs(
            this.vmtree.address,
            this.linkNode.address,
            this.linkPayer.address, 
            this.linkPayment
        );

        verifiableEndSubtrees = await this.vmtree.getFilledSubtrees();
        verifiableEndSubtrees.forEach((subtree, i) => {
            expect(subtree).to.be.equal(this.endSubtrees[i]);
        })
    });

    it('should have correct link balances after performMassUpdate', async () => {
        expect(await this.arborist.linkPayerBalance(this.linkPayer.address))
            .to.be.equal(this.linkPayment.mul(9));

        expect(await this.arborist.linkNodeBalance(this.linkNode.address))
            .to.be.equal(this.linkPayment);
    });

    it('should allow linkNode to withdraw payment', async () => {
        await expect(this.arborist.connect(this.linkNode).collectLinkNodeLink(
            this.linkNode.address
        )).to.emit(this.arborist, 'LinkCollected').withArgs(
            this.arborist.address,
            this.linkNode.address,
            this.linkPayment
        );

        expect(await this.linkToken.balanceOf(this.linkNode.address))
            .to.be.equal(this.linkPayment);
    });

    it('should deposit more commitments', async () => {
        
    });
});