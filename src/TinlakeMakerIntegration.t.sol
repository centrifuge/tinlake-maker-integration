pragma solidity ^0.5.12;

import "ds-test/test.sol";

import "./TinlakeMakerIntegration.sol";

contract TinlakeMakerIntegrationTest is DSTest {
    TinlakeMakerIntegration integration;

    function setUp() public {
        integration = new TinlakeMakerIntegration();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
