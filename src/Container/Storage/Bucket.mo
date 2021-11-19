import Array "mo:base/Array";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Hex "../Module/Hex";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Prim "mo:⛔";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import SHA256 "../Module/SHA256";
import SM "mo:base/ExperimentalStableMemory";
import Text "mo:base/Text";
import TrieMap "mo:base/TrieMap";
import Types "../Module/Types";
import Stack "mo:base/Stack";
import Blob "mo:base/Blob";

shared(installer) actor class Bucket() = this{
	private type Asset = Types.Asset;
	private type AssetExt = Types.AssetExt;
	private type Chunk = Types.Chunk;
	private type PUT = Types.PUT;
	private type GET = Types.GET;
	private type Extension = Types.FileExtension;
	private type BufferAsset = Types.BufferAsset;
	private let MAX_PAGE_NUMBER : Nat32 = 65535;
	private let PAGE_SIZE = 65536; // Byte
	private let THRESHOLD = 4294901760; // 65535 * 65536
	private let MAX_UPDATE_SIZE = 1992295;
	private let MAX_QUERY_SIZE = 3144728; // 3M - 1KB
	private let UPGRADE_SLICE = 6000; // 暂定
	private var offset = 0; // [0, 65535*65536-1]
	private var buffer_canister_id = ""; // buffer canister id text
	private var assets = TrieMap.TrieMap<Text, Asset>(Text.equal, Text.hash);
	private var buffer = HashMap.HashMap<Text, BufferAsset>(10, Text.equal, Text.hash);  

	private func _inspect(data : Blob) : Result.Result<Nat, Text>{
		var size = data.size();
		if(size <= _avlSM()){
			#ok(size)
		}else{
			#err("insufficient memory")
		}
	};

	private func _digest(pred : [var Nat8], nd : [Nat8], received : Nat){
		var i = received * 32;
		for(e in nd.vals()){
			pred[i] := e;
			i := i + 1;
		};
	};

 	/*offset : Nat, total_size : Nat*/
	// wirte page field -> query page field
	private func _pageField(buffer_page_field : [(Nat, Nat)], total_size : Nat) : [[(Nat, Nat)]]{
		// 正好够 size / query_size 页
		var arrSize = 0; 
		if(total_size % MAX_QUERY_SIZE == 0){
			arrSize := total_size / MAX_QUERY_SIZE;
		}else{
			arrSize := total_size / MAX_QUERY_SIZE + 1;
		};
		var res = Array.init<[(Nat, Nat)]>(arrSize, []);
		var i = 0;
		var rowSize = 0;
		for((start, size) in buffer_page_field.vals()){
			if(rowSize + size <= MAX_QUERY_SIZE){
				res[i] := Array.append(res[i], [(start, size)]);
			}else{
				i += 1;
				res[i] := [(start, size)];
			};
			rowSize += size;
		};
		Array.freeze<[(Nat, Nat)]>(res)
	};

	// available stable wasm memory
	private func _avlSM() : Nat{
		THRESHOLD - offset
	};

	// return page field
	private func _putSM(data : Blob, size : Nat) : (Nat, Nat){
		// 看本页的内存还剩多少
		let page_left = if(offset >= PAGE_SIZE){
			PAGE_SIZE - offset % PAGE_SIZE
		}else{
			ignore SM.grow(1);
			PAGE_SIZE
		};

		let res = (offset, size);

		// 如果够则记录到本页， 如果不够就grow
		if(size <= page_left){
			//本页够
			SM.storeBlob(Nat32.fromNat(offset), data);
			offset += data.size();
		}else if((size - page_left) % PAGE_SIZE > 0){
			// 本页不够，grow的page足够
			assert(SM.size() <= MAX_PAGE_NUMBER);
			ignore SM.grow(Nat32.fromNat(size / PAGE_SIZE + 1));
			SM.storeBlob(Nat32.fromNat(offset), data);
			offset += data.size();
		}else{
			//正好够
			assert(SM.size() <= MAX_PAGE_NUMBER);
			ignore SM.grow(Nat32.fromNat(size / PAGE_SIZE));
			SM.storeBlob(Nat32.fromNat(offset), data);
			offset += data.size();
		};
		res
	};

	private func _getSM(field : [(Nat, Nat)]) : [Blob]{
		let res = Array.init<Blob>(field.size(), "" : Blob);
		var i = 0;
		for((start, size) in field.vals()){
			res[i] := SM.loadBlob(Nat32.fromNat(start), size);
			i := i + 1;
		};
		Array.freeze<Blob>(res)
	};

	private func _assetExt(asset : Asset) : AssetExt{
		{
			bucket_id = Principal.fromActor(this);
			key = asset.key;
			total_size = asset.total_size;
			file_extension = asset.file_extension;
			need_query_times = asset.page_field.size();
		}
	};

	private func _key(digests : [Nat8]) : Text{
		Hex.encode(SHA256.sha256(digests))
	};

	/**
	*	inspect file format and file size
	*	put file data into stable wasm memory
	*	put file asset into assets
	*/
	private func _init(chunk : Chunk, chunk_num : Nat, extension : Extension) : Result.Result<AssetExt, Text> {
		var size_ = 0;
		var field = (0,0);
		// inspect data & put data into stable memory
		switch(_inspect(chunk.data)){
			case(#ok(size)){
				size_ := size;
				field := _putSM(chunk.data, size);
			};
			case(#err(e)){ return #err(e) };
		};
		// get init key
		let key = _key(chunk.digest);

		if(chunk_num == 0){
			#err("wrong chunk num value 0")
		}else if(chunk_num == 1){
			let asset = {
				key = key;
				total_size = size_;
				page_field = [[field]];
				file_extension = extension;
			};
			assets.put(key, asset);
			#ok(_assetExt(asset))
		}else{
			var digest = Array.init<Nat8>(chunk_num*32, 0);
			// 返回的时候可能返回的是包含两个元素的blob数组， 前端拼接就可以了
			var page_field = Array.init<(Nat, Nat)>(chunk_num, (0,0));
			page_field[0] := field;
			let buffer_asset = {
				key = key;
				file_extension = extension;
				digest = digest;
				chunk_number = chunk_num;
				var page_field = page_field;
				var total_size = size_;
				var received = 1;
			};
			buffer.put(key, buffer_asset);
			#ok(_assetExt(
				{
					key = key;
					page_field = [Array.freeze<(Nat, Nat)>(page_field)];
					total_size = size_;
					file_extension = extension;
				}
			))
		}
	};

	/**
	*	get file asset
	*	inspect file format and file size
	*	put file chunk into stable wasm memory
	*	change asset field
	*	put file asset into assets
	*/
	private func _append(key : Text, chunk : Chunk, order : Nat) : Result.Result<AssetExt, Text> {
		var size_ = 0;
		var field = (0,0);
		if(order < 1){ return #err("wrong order") };
		// inspect data & put data into stable memory
		switch(_inspect(chunk.data)){
			case(#ok(size)){
				size_ := size;
				field := _putSM(chunk.data, size);
			};
			case(#err(e)){ return #err(e) };
		};

		switch(buffer.get(key)){
			case null { #err("file didn't initralize") };
			case (?a){
				// final : buffer asset -> asset
				if(a.received + 1 == a.chunk_number){
					_digest(a.digest, chunk.digest, a.received);
					a.received += 1;
					a.page_field[order] := field;
					let total_size = a.total_size + size_;
					let digests = Array.freeze(a.digest);
					let page_field = Array.freeze(a.page_field);
					let asset = {
						key = _key(digests);
						page_field = _pageField(page_field, total_size);
						total_size = total_size;
						file_extension = a.file_extension;
					};
					assets.put(asset.key, asset);
					buffer.delete(a.key);
					Debug.print("final asset" # debug_show(asset));
					#ok(_assetExt(asset))
				}else{
					_digest(a.digest, chunk.digest, a.received);
					a.received += 1;
					a.page_field[order] := field;
					a.total_size += size_;
					#ok(_assetExt(
						{
							key = a.key;
							page_field = [Array.freeze<(Nat, Nat)>(a.page_field)];
							total_size = size_;
							file_extension = a.file_extension;
						}
					))
				}
			}
		}
	};

	public shared({caller}) func put(
		put : PUT
	) : async Result.Result<AssetExt, Text>{
		switch(put){
			case(#init(segment)){
				switch(_inspect(segment.chunk.data)){
					case(#ok(_)){ _init(segment.chunk, segment.chunk_number, segment.file_extension) };
					case(#err(info)){ #err(info) }
				}
			};
			case(#append(segment)){
				switch(_inspect(segment.chunk.data)){
					case(#ok(_)){ _append(segment.key, segment.chunk, segment.order) };
					case(#err(info)){ #err(info) }
				}
			};
		}
	};
	
	public shared({caller}) func setBufferCanister(p : Text) : async (){
		buffer_canister_id := p;
	};

	public shared({caller}) func wallet_receive() : async Nat{
		Cycles.accept(Cycles.available())
	};

	// data : [flag, offset + size - 1]
	public query({caller}) func get(
		g : GET
	) : async Result.Result<[Blob], Text>{
		switch(assets.get(g.key)){
			case(null){ #err("wrong key") };
			case(?asset){
				// 安全检测
				if(g.flag > asset.page_field.size()){
					#err("wrong flag")
				}else{
					Debug.print("page field : " # debug_show(asset.page_field));
					let field = asset.page_field[g.flag];
					Debug.print("bucket get field : " # debug_show(field));
					#ok(_getSM(field))
				}
			};
		}
	};

	public query({caller}) func getAssetExt(key : Text) : async Result.Result<AssetExt, Text>{
		switch(assets.get(key)){
			case null { #err("wrong key") };
			case(?asset){ #ok(_assetExt(asset)) };
		}
	};

	public query({caller}) func canisterState() : async Text{
		"RTS Heap Size : " # debug_show(Prim.rts_heap_size())
		# "RTS Memory Size : " # debug_show(Prim.rts_memory_size())
		# "Balance" # debug_show(Cycles.balance())
	};
	
};