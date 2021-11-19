#!/bin/bash
dfx stop
dfx start --background --clean --emulator
dfx deploy
dfx canister call test start
dfx canister call test test_get
dfx canister call test test_init
for i in `seq 4`
do
    dfx canister call test test_append
done
dfx canister call test test_get