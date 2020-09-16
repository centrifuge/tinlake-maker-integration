pragma solidity ^0.5.12;

import "ds-test/test.sol";
import {DssDeployTestBase, DSValue} from "dss-deploy/DssDeploy.t.base.sol";
import "dss-add-ilk-spell/DssAddIlkSpell.sol";

import "tinlake/test/system/base_system.sol";

import {TinlakeJoin} from "tinlake-maker-lib/join.sol";
import {TinlakeFlipper} from "tinlake-maker-lib/flip.sol";

import {PipLike} from "dss/spot.sol";

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
        deployLenderMockBorrower(address(this));
        createInvestorUser();

        uint seniorAmount =  82 ether;
        uint juniorAmount = 18 ether;
        seniorSupply(seniorAmount, seniorInvestor);
        juniorSupply(juniorAmount);
        hevm.warp(now + 1 days);

        coordinator.closeEpoch();
        // no submission required
        // submission was valid
        assertTrue(coordinator.submissionPeriod() == false);
        // inital token price is ONE
        (uint payoutCurrencyAmount, uint payoutTokenAmount, uint remainingSupplyCurrency,  uint remainingRedeemToken) = seniorInvestor.disburse();

        dropJoin = new TinlakeJoin(address(vat), ilk, address(seniorToken));
        dropPip = new DSValue();
        dropPip.poke(bytes32(uint(300 ether)));
        dropFlip = new TinlakeFlipper(address(vat), ilk);
        dropFlip.rely(address(pause.proxy()));
        dropFlip.deny(address(this));

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

        seniorToken.approve(address(dropJoin), uint(-1));
    }

    function seniorSupply(uint currencyAmount, Investor investor) public {
        seniorMemberlist.updateMember(seniorInvestor_, safeAdd(now, 8 days));
        currency.mint(address(seniorInvestor), currencyAmount);
        investor.supplyOrder(currencyAmount);
        (,uint supplyAmount, ) = seniorTranche.users(address(investor));
        assertEq(supplyAmount, currencyAmount);
    }

    function juniorSupply(uint currencyAmount) public {
        juniorMemberlist.updateMember(juniorInvestor_, safeAdd(now, 8 days));
        currency.mint(address(juniorInvestor), currencyAmount);
        juniorInvestor.supplyOrder(currencyAmount);
        (,uint supplyAmount, ) = juniorTranche.users(juniorInvestor_);
        assertEq(supplyAmount, currencyAmount);
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
        assertEq(dai.balanceOf(address(this)), 0);
        dropJoin.join(address(this), 1 ether);

        vat.frob(ilk, address(this), address(this), address(this), 1 ether, 100 ether);

        vat.hope(address(daiJoin));
        daiJoin.exit(address(this), 100 ether);
        assertEq(dai.balanceOf(address(this)), 100 ether);
    }

    function testFlip() public {
        this.file(address(cat), ilk, "lump", 1 ether); // 1 unit of collateral per batch
        this.file(address(cat), ilk, "chop", ONE);
        dropJoin.join(address(this), 1 ether);
        vat.frob(ilk, address(this), address(this), address(this), 1 ether, 200 ether); // Maximun DAI generated
        dropPip.poke(bytes32(uint(300 ether - 1))); // Decrease price in 1 wei
        spotter.poke(ilk);
        assertEq(vat.gem(ilk, address(dropFlip)), 0);
        uint batchId = cat.bite(ilk, address(this));
        assertEq(vat.gem(ilk, address(dropFlip)), 1 ether);

        address(user1).transfer(10 ether);
        user1.doEthJoin(address(weth), address(ethJoin), address(user1), 10 ether);
        user1.doFrob(address(vat), "ETH", address(user1), address(user1), address(user1), 10 ether, 1000 ether);

        address(user2).transfer(10 ether);
        user2.doEthJoin(address(weth), address(ethJoin), address(user2), 10 ether);
        user2.doFrob(address(vat), "ETH", address(user2), address(user2), address(user2), 10 ether, 1000 ether);

        user1.doHope(address(vat), address(dropFlip));
        user2.doHope(address(vat), address(dropFlip));

        user1.doTend(address(dropFlip), batchId, 1 ether, rad(100 ether));
        user2.doTend(address(dropFlip), batchId, 1 ether, rad(140 ether));
        user1.doTend(address(dropFlip), batchId, 1 ether, rad(180 ether));
        user2.doTend(address(dropFlip), batchId, 1 ether, rad(200 ether));
    }
}
