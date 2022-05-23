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
        this.signer = await ethers.getSigner();
        this.linkPayment = ethers.utils.parseUnits('0.1');

        this.leaves = unsafeRandomLeaves(11).map(bn => bn.toString());
        this.startSubtrees = calculateSubtrees(mimcSponge, 20, 0, []);
        this.singleEndSubtrees = calculateSubtrees(mimcSponge, 20, 0, [this.leaves[0]]);
        this.endSubtrees = calculateSubtrees(mimcSponge, 20, 0, this.leaves);
        
        // deploy contracts
        this.linkToken = await deploy("LinkToken");
        this.arborist = await deploy(
            "Arborist",
            [this.linkPayment, this.linkToken.address]
        );
    });

    it('signer balance should be total supply', async () => {
        expect(await this.linkToken.balanceOf(this.signer.address))
            .to.be.equal(await this.linkToken.totalSupply());       
    });

    it('should deploy a vmtree using LINKs transferAndCall', async () => {
        await this.linkToken.transferAndCall(
            this.arborist.address,
            this.linkPayment.mul(100),
            hexPadLeft(this.signer.address)
        );
        const [ log ] = await this.arborist.queryFilter('VMTreeCloned');

        const vmTreeFactory = await ethers.getContractFactory('VMTree');
        this.vmtree = new ethers.Contract(
            log.args.tree, vmTreeFactory.interface, this.signer
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
        await this.vmtree.update(p, newSubtrees);

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
        console.time('mass update proof');
        this.massUpdateProof = await calculateMassUpdateProof(
            "./circuits/massUpdate.wasm",
            "./circuits/massUpdate.zkey",
            1,
            this.leaves.slice(1),
            this.singleEndSubtrees,
            this.endSubtrees
        );
        console.timeEnd('mass update proof');
        const result = await verifyProof(
            massUpdateVerifier,
            this.massUpdateProof.publicSignals,
            this.massUpdateProof.proof
        );
        expect(result).to.be.true;
    });

    it('should update the VMTree for 10 deposits', async () => {
        const { proof, publicSignals } = this.massUpdateProof;
        const { p, newSubtrees } = toVmtMassUpdateSolidityInput(
            proof,
            publicSignals
        );

        await this.vmtree.performMassUpdate(
            p,
            newSubtrees
        );

        verifiableEndSubtrees = await this.vmtree.getFilledSubtrees();
        verifiableEndSubtrees.forEach((subtree, i) => {
            expect(subtree).to.be.equal(this.endSubtrees[i]);
        })

    });

});