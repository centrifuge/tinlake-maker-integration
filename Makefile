all    :; dapp build
clean  :; dapp clean
update:
	git submodule foreach --recursive --quiet '[[ ${PWD##*/} == "ds-test" ]] && echo $PWD && git checkout eb7148d43c1ca6f9890361e2e2378364af2430ba; exit 0'
	git submodule foreach --recursive --quiet '[[ ${PWD##*/} == "ds-note" ]] && echo $PWD && git checkout c673c9d1a1464e973db4489221e22dc5b9b02319; exit 0'
test: update
	dapp --use solc:0.5.15 test
deploy :; dapp create TinlakeMakerIntegration
