module{

    // data 设为1.9 M (1992295) / chunk
    public type Chunk = {
        digest : [Nat8]; // SHA256 of chunk
        data : Blob;
    };
    
    public type AssetExt = {
        bucket_id : Principal;
        key : Text;
        total_size : Nat;
        file_extension : FileExtension;
        need_query_times : Nat; // need query times for one file
    };

    /**
    *   wasm page 暂时做成连续存储， 即只增不删
    */
    public type Asset = {
        key :  Text; // Key = SHA256(chunk key)
        page_field : [[(Nat, Nat)]]; // (offset, size)->3M/slice
        total_size : Nat; // file total size
        file_extension : FileExtension;
    };

    public type BufferAsset = {
        key :  Text; // Key = SHA256(chunk key)
        file_extension : FileExtension;
        digest : [var Nat8]; // Chunk SHA256 Digest Array [a] + [b] -> [a,b], 这个不保存
        chunk_number : Nat;
        var page_field : [var (Nat, Nat)]; // (offset, size)->3M/slice
        var total_size : Nat; // file total size
        var received : Nat; // received put
    };

    public type PUT = {
        #init : {
            chunk : Chunk;
            // chunk number 包含init这个chunk
            chunk_number : Nat;
            file_extension : FileExtension;
        };
        #append : {
            key : Text;
            chunk : Chunk;
            // order 从1开始，从小到大
            order : Nat;
        };
    };

    public type GET = {
        key : Text;
        // 在一次请求中， 第几次请求这个文件
        // 如果接着上次的请求， flag 取值区间为 [0, need_query_size - 1]
        // 若只需要query一次， 那么flag填0即可
        // 如果要重新开始请求， 就从1开始。
        flag : Nat;
    };

    public type FileExtension = {
        #txt;
        #docs;
        #doc;
        #ppt;
        #jpeg;
        #jpg;
        #png;
        #gif;
        #svg;
        #mp3;
        #wav;
        #aac;
        #mp4;
        #avi;
    };



};