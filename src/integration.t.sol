pragma solidity ^0.5.12;

import "ds-test/test.sol";
import { DssDeployTestBase, DSValue } from "dss-deploy/DssDeploy.t.base.sol";
import "dss-add-ilk-spell/DssAddIlkSpell.sol";

import { BaseSystemTest } from "tinlake/test/system/base_system.sol";
import { TokenLike } from "tinlake/test/system/setup.sol";
import { Hevm } from "tinlake/test/system/interfaces.sol";

import { TinlakeJoin } from "tinlake-maker-lib/join.sol";
import { TinlakeFlipper } from "tinlake-maker-lib/flip.sol";

import { PipLike } from "dss/spot.sol";

contract DssAddIlkSpellTest is DssDeployTestBase, BaseSystemTest {
    Hevm public hevm;

    DssAddIlkSpell spell;

    bytes32 constant ilk = "TEST-DROP"; // New Collateral Type
    TinlakeJoin     dropJoin;
    TinlakeFlipper  dropFlip;
    DSValue         dropPip;

    function setUp() public {
        DssDeployTestBase.setUp();
        deploy();

        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(1234567);

        currency = TokenLike(address(dai));
        currency_ = address(dai);

        // mint 600 DAI with ETH to set up the pool
        weth.deposit.value(10 ether)();
        weth.approve(address(ethJoin), uint(-1));
        ethJoin.join(address(this), 10 ether);
        vat.frob("ETH", address(this), address(this), address(this), 5 ether, 600 ether);
        vat.hope(address(daiJoin));
        daiJoin.exit(address(this), 600 ether);

        // Set up Tinlake contracts
        deployLenderMockBorrower(address(this));


        // Set up spell
        dropJoin = new TinlakeJoin(address(vat), ilk, address(seniorToken));
        dropPip = new DSValue();
        dropPip.poke(bytes32(uint(300 ether)));
        dropFlip = new TinlakeFlipper(address(vat), ilk, address(seniorToken), address(dai), address(dropJoin), address(daiJoin), address(seniorOperator), address(seniorTranche));
        dropFlip.rely(address(pause.proxy()));
        dropFlip.deny(address(this));
        seniorMemberlist.updateMember(address(dropJoin), safeAdd(now, 20 days));
        seniorMemberlist.updateMember(address(dropFlip), safeAdd(now, 20 days));

        spell = new DssAddIlkSpell(
            ilk,
            address(pause),
            [
                address(vat),
                address(cat),
                address(jug),
                address(spotter),
                address(end),
                address(dropJoin),
                address(dropPip),
                address(dropFlip)
            ],
            [
                10000 * 10 ** 45, // line
                1500000000 ether, // mat
                1.05 * 10 ** 27, // tax
                ONE, // chop
                10000 ether // lump
            ]
        );

        authority.setRootUser(address(spell), true);

        spell.schedule();
        spell.cast();

        createInvestorUser();

        juniorMemberlist.updateMember(juniorInvestor_, safeAdd(now, 8 days));
        currency.transferFrom(address(this), address(juniorInvestor), 18 ether);
        juniorInvestor.supplyOrder(18 ether);

        seniorMemberlist.updateMember(address(this), safeAdd(now, 8 days));
        currency.approve(address(seniorTranche), 82 ether);
        seniorOperator.supplyOrder(82 ether);
        hevm.warp(now + 1 days);
        coordinator.closeEpoch();
        seniorOperator.disburse();

        seniorToken.approve(address(dropJoin), uint(-1));
    }

    function testVariables() public {
        (,,,uint line,) = vat.ilks(ilk);
        assertEq(line, uint(10000 * 10 ** 45));
        (PipLike pip, uint mat) = spotter.ilks(ilk);
        assertEq(address(pip), address(dropPip));
        assertEq(mat, uint(1500000000 ether));
        (uint tax,) = jug.ilks(ilk);
        assertEq(tax, uint(1.05 * 10 ** 27));
        (address flip, uint chop, uint lump) = cat.ilks(ilk);
        assertEq(flip, address(dropFlip));
        assertEq(chop, ONE);
        assertEq(lump, uint(10000 ether));
        assertEq(vat.wards(address(dropJoin)), 1);
    }

    function testFrob() public {
        assertEq(dai.balanceOf(address(this)), 500 ether);
        dropJoin.join(address(this), 1 ether);

        vat.frob(ilk, address(this), address(this), address(this), 1 ether, 100 ether);

        vat.hope(address(daiJoin));
        daiJoin.exit(address(this), 100 ether);
        assertEq(dai.balanceOf(address(this)), 600 ether);
    }

    function testFlip() public {
        assertEq(address(seniorTranche), address(seniorOperator.tranche()));
        this.file(address(cat), ilk, "lump", uint(1 ether)); // 1 unit of collateral per batch
        this.file(address(cat), ilk, "chop", ONE);
        dropJoin.join(address(this), 1 ether);
        vat.frob(ilk, address(this), address(this), address(this), 1 ether, 1 ether); // Maximun DAI generated
        dropPip.poke(bytes32(uint(1)));
        spotter.poke(ilk);
        assertEq(vat.gem(ilk, address(dropFlip)), 0);
        uint batchId = cat.bite(ilk, address(this));
        (uint epoch, uint supplyOrd, uint redeemOrd) = seniorTranche.users(address(dropFlip));
        assertEq(redeemOrd, 1 ether);

        hevm.warp(now + 1 days);
        coordinator.closeEpoch();

        assertEq(dropFlip.tab(), 1 ether * 10**27);
        dropFlip.take();
        assertEq(dropFlip.tab(), 0);

    }
}
