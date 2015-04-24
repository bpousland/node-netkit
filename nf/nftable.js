var nlnf = require('./nlnetfilter.js');

nftable = {

	table: function(opts, cb) {
		var that = this;

		nftable.build_command(opts,function(err){
			if(err) {
				cb(err);
			} else {
				console.dir(opts);

				nlnf.netfilterSend.call(that, null, opts,
					nlnf.nf.attrs.table, function(err,result){
					if(err) {
						return cb(err);
					} else {
						return cb(null, nftable.parse_table(result,opts));
					}
				});
			}
		});
	},

	parse_table: function(data,opts) {
		var table = {};

		table = data;

		// table.table = opts['params']['name'];
		// table.attributes = data['genmsg'];
		// table.attributes['_family'] = nlnf.get_family_str(data['genmsg']['_family']);
		return table;
	},

	build_command: function(opts,cb) {

		console.dir(opts);

		nftable.set_cmd(opts,cb);
		nlnetfilter.set_family(opts,cb);
		nftable.set_type(opts,cb);

		console.dir(opts);
		cb();
	},

	set_cmd: function(opts, cb) {

		var command = opts['command'];
		console.log("command = " + command);

		switch(command) {
			case "list":
				opts['cmd'] = nf.NFT_MSG_GETTABLE;
				break;
			case "get":
				opts['cmd'] = nf.NFT_MSG_GETTABLE;
				break;
			case "add":
				opts['cmd'] =  nf.NFT_MSG_NEWTABLE;
				break;
			case "del":
				opts['cmd'] =  nf.NFT_MSG_DELTABLE;
				break;
			case "update":
				opts['cmd'] =  nf.NFT_MSG_NEWTABLE;
				break;
			default:
				return cb(new Error(command +
					" command not supported: get, add, del, update"));
				break;
		}
	},

	set_type: function(opts, cb) {

		var command = opts['command'];
		console.log("command = " + command);

		switch(command) {
			case "list":
				opts['type_flags'] = nl.NLM_F_ROOT | nl.NLM_F_MATCH;
				break;
			case "get":
				opts['type_flags'] = nl.NLM_F_ACK;
				break;
			case "add":
				opts['type_flags'] =  nl.NLM_F_ACK;
				break;
			case "del":
				opts['type_flags'] =  nl.NLM_F_ACK;
				break;
			case "update":
				opts['type_flags'] =  nl.NLM_F_ACK;
				break;
			default:
				return cb(new Error(command +
					" command not supported: get, add, del, update"));
				break;
		}
	},

};

module.exports = nftable;