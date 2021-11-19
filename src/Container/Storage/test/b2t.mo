import Types "../Module/Types";
import SHA256 "../Module/SHA256";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Interface "Module/Interface";
import Option "mo:base/Option";
import Cycles "mo:base/ExperimentalCycles";
import Bucket "../Storage/Bucket";

actor bucket2test{

    let metadata = Array.freeze(Array.init<Nat8>(1000, 0xff));
    let blob = Blob.fromArray(metadata);
    let ic = actor "aaaaa-aa" : Interface.ICActor;
    let owner = Principal.fromText("slqa4-73acs-65lmr-d52by-ugflp-4dm7p-i2omo-yrw65-5d7mn-qqcbh-lae"); // local test owner
    let temp = Principal.fromText("jdil2-3yaaa-aaaai-qabjq-cai");

    stable var bucket = Principal.fromText("aaaaa-aa");
    var asset : ?Types.AssetExt = null;
    var key = "";
    var order = 1;
    var flag = 0;

    let test_chunk = {
        digest = SHA256.sha256(metadata);
        data = blob;
    };

    let init_chunk = {
        chunk = test_chunk;
        chunk_number = 5;
        file_extension = #png;
    };

    public shared(msg) func update(canister_id : Principal) : async (){
        await (ic.update_settings({
            canister_id = canister_id; 
            settings = {
                controllers = ?[owner, Principal.fromActor(bucket2test), temp];
                compute_allocation = ?0;
                memory_allocation = ?0;
                freezing_threshold = ?31_540_000
            }
        }))
    };

    // public shared(msg) func setBucket() : async (){
    //     bucket := Principal.fromText("xlio4-2yaaa-aaaai-qa35q-cai");
    // };

    public shared(msg) func start() : async Text{
        //Cycles.add(2000000000000);
        let b = await Bucket.Bucket();
        bucket := Principal.fromActor(b);
        await update(bucket);
        "Bucket Principal : " # debug_show(bucket);
    };

    public shared(msg) func test_init() : async Text{
        let b = actor (Principal.toText(bucket)) : Bucket.Bucket;
        switch(await b.put(#init(init_chunk))){
            case (#err(_)){};
            case (#ok(a)){ asset := ?a };
        };
        key := Option.unwrap(asset).key;
        debug_show("key is : " # key) # "asset is : " # debug_show(asset)
    };

    public shared(msg) func test_append() : async Text{
        let b = actor (Principal.toText(bucket)) : Bucket.Bucket;
        let append_chunk = {
            chunk = test_chunk;
            key = key;
            order = order;
        };
        switch(await b.put(#append(append_chunk))){
            case (#err(_)){};
            case (#ok(a)){ asset := ?a };
        };
        order := order + 1;
        key := Option.unwrap(asset).key;
        flag := Option.unwrap(asset).need_query_times;
        debug_show("append key is " # key) # "asset is : " # debug_show(asset) 
    };

    public shared(msg) func test_get() : async Text{
        let b = actor (Principal.toText(bucket)) : Bucket.Bucket;
        var s = 0;
        Debug.print(switch(await b.get({key = key; flag = flag - 1})){
            case (#ok(v)){
                for(d in v.vals()){
                    s += d.size()
                };
                "return data size : " # debug_show(s)
            };
            case(_){"err size"};
        });
        Debug.print("flag : " # debug_show(flag));
        "Get Value : " # debug_show(await b.get({key = key; flag = flag - 1}))
    };

    // public shared func wallet_receive() : async Nat{
    //     Cycles.accept(//Cycles.available())
    // };

};