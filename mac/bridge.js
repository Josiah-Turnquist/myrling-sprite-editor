// Injected by the Mac app before the page loads. WebKit has no File System Access API,
// so this fills in the one corner of it the editor uses: showOpenFilePicker and the
// handles it returns. The page cannot tell the difference, and the same index.html
// keeps working unchanged in a plain browser, where this file is never loaded.
(function () {
  var port = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.eldermyr;
  if (!port || window.showOpenFilePicker) return;

  function bytesFromB64(b64) {
    var bin = atob(b64), a = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) a[i] = bin.charCodeAt(i);
    return a;
  }
  function b64FromBuffers(bufs) {
    var total = 0, i, j;
    for (i = 0; i < bufs.length; i++) total += bufs[i].byteLength;
    var all = new Uint8Array(total), at = 0;
    for (i = 0; i < bufs.length; i++) { all.set(new Uint8Array(bufs[i]), at); at += bufs[i].byteLength; }
    var s = '';
    for (j = 0; j < all.length; j += 0x8000) s += String.fromCharCode.apply(null, all.subarray(j, j + 0x8000));
    return btoa(s);
  }
  function makeHandle(rec) {
    return {
      kind: 'file',
      name: rec.name,
      getFile: function () {
        return Promise.resolve(new File([bytesFromB64(rec.bytes)], rec.name, { type: 'image/png' }));
      },
      queryPermission: function () { return Promise.resolve('granted'); },
      requestPermission: function () { return Promise.resolve('granted'); },
      createWritable: function () {
        var parts = [];
        return Promise.resolve({
          write: function (blob) { return blob.arrayBuffer().then(function (ab) { parts.push(ab); }); },
          close: function () {
            return port.postMessage({ op: 'write', id: rec.id, bytes: b64FromBuffers(parts) })
              .then(function () { });
          }
        });
      }
    };
  }
  window.showOpenFilePicker = function () {
    return port.postMessage({ op: 'pick' }).then(function (r) {
      if (!r || r.cancelled || !r.files || !r.files.length) {
        var e = new Error('The picker was closed');
        e.name = 'AbortError';
        throw e;
      }
      return r.files.map(makeHandle);
    });
  };
})();
