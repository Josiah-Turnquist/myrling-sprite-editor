// Injected by the Mac app before the page loads. WebKit has no File System Access API,
// so this fills in the one corner of it the editor uses: showOpenFilePicker and the
// handles it returns. The page cannot tell the difference, and the same index.html
// keeps working unchanged in a plain browser, where this file is never loaded.
(function () {
  var port = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.eldermyr;
  if (!port || window.showOpenFilePicker) return;
  // the page can dress for the Mac: the title bar toolbar and the menu bar carry the
  // image operations here, so the page's own copies of them stay out of the way
  document.documentElement.classList.add('mac');

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
      dir: rec.dir || '',   // where the file really lives, so the page can say so
      getFile: function () {
        if (!rec.bytes) return Promise.reject(new Error('no bytes came with this handle'));
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
  // dropped files: the app noted where they came from as they crossed the window edge;
  // the page asks here, by name, and gets a handle it can write back through. The File
  // itself already travelled with the drop, so the handle needs no bytes of its own.
  if (window.DataTransferItem && !DataTransferItem.prototype.getAsFileSystemHandle) {
    DataTransferItem.prototype.getAsFileSystemHandle = function () {
      var f = this.getAsFile ? this.getAsFile() : null;
      if (!f || !f.name) return Promise.resolve(null);
      return port.postMessage({ op: 'claim', name: f.name }).then(function (r) {
        return r && r.id ? makeHandle({ id: r.id, name: f.name, dir: r.dir }) : null;
      }, function () { return null; });
    };
  }
  // the folder picker: a chosen directory comes back as a handle whose getFileHandle
  // hands out writable file handles inside it, which is all the page asks of it
  window.showDirectoryPicker = window.showDirectoryPicker || function () {
    return port.postMessage({ op: 'pickdir' }).then(function (r) {
      if (!r || r.cancelled || !r.id) {
        var e = new Error('The picker was closed');
        e.name = 'AbortError';
        throw e;
      }
      return {
        kind: 'directory',
        name: r.name,
        dir: r.path,
        queryPermission: function () { return Promise.resolve('granted'); },
        requestPermission: function () { return Promise.resolve('granted'); },
        getFileHandle: function (fname) {
          return Promise.resolve({
            kind: 'file',
            name: fname,
            dir: r.path,
            createWritable: function () {
              var parts = [];
              return Promise.resolve({
                write: function (blob) { return blob.arrayBuffer().then(function (ab) { parts.push(ab); }); },
                close: function () {
                  return port.postMessage({ op: 'writeto', dir: r.id, name: fname, bytes: b64FromBuffers(parts) })
                    .then(function () { });
                }
              });
            }
          });
        }
      };
    });
  };
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
