import Array "mo:base/Array";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Hex "../Module/Hex";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Types "../Module/Types";
import TrieSet "mo:base/TrieSet";
import Trie "mo:base/Trie";
import TrieMap "../Module/TrieMap";
import Hash "mo:base/Hash";
import Text "mo:base/Text";

 shared({caller}) actor class AssetStorage() = this{

    private type SharedAsset = Types.SharedAsset;

	private let MAX_QUERY_SIZE = 3144728; // 3M - 1KB
    private let SLICE = 6000; // ~ 3 MiB / 300 byte

    private var offsets = HashMap.HashMap<Principal, Nat>(10, Principal.equal, Principal.hash);
    // canister_id <-> (offset, Assets)
    private var map = HashMap.HashMap<Principal, Trie.Trie<Text, SharedAsset>>(10, Principal.equal, Principal.hash);

    stable var offsets_entries : [(Principal, Nat)] = [];
    stable var map_entries : [(Principal, Trie.Trie<Text, SharedAsset>)] = [];

    private func _hash(a : [SharedAsset]) : Hash.Hash{
        Text.hash(a[0].key)
    };

    private func _eq(a : [SharedAsset], b : [SharedAsset]) : Bool{
        a[0].key == b[0].key
    };

    // put offset
    private func _puto(p : Principal, o : Nat){
        offsets.put(p,o);
    };

    // put asset into map
    private func _putm(p : Principal, a : Trie.Trie<Text, SharedAsset>){
        map.put(p, a);
    };

    /**
    *   分 1.99 M最大每次，将数据存到这个Canister
    */
    public shared({caller}) func putAsset(asset : Trie.Trie<Text, SharedAsset>) : async Result.Result<Text, Text>{
        _putm(caller, asset);
        #ok("")
    };

    public shared({caller}) func putOffSet(offset : Nat) : async Result.Result<Text, Text>{
        _puto(caller, offset);
        #ok("")
    };

    public query({caller}) func getOffSet() : async Result.Result<Nat, Text>{

        let val = offsets.get(caller);

        switch(val){
            case (?offset) { #ok(offset) };
            case (_) { #err("") };
        };

    };

    public query({caller}) func getAsset() : async Result.Result<Trie.Trie<Text, SharedAsset>, Text>{
        let val = map.get(caller);

        switch(val){
            case (?assetMap) {
                #ok(assetMap)
            };
            case null { #err("") };
        };
    };

    system func preupgrade(){
        offsets_entries := Iter.toArray(offsets.entries());

        map_entries := Iter.toArray(map.entries());
    };

    system func postupgrade(){
        offsets := HashMap.fromIter(offsets_entries.vals(), 10, Principal.equal, Principal.hash);

        map := HashMap.fromIter(map_entries.vals(), 10, Principal.equal, Principal.hash);

        offsets_entries := [];
        map_entries := [];
    };

};