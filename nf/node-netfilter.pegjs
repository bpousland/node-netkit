/*
See: https://wiki.archlinux.org/index.php/Nftables

list
  all tables [family]
  table [family] <name>
  chain [family] [<table> <name>]
  rule  [family] [<table>] [<chain>]

add
  table [family] <name>
  chain [family] <table> <name> [chain definitions]
  rule [family] <table> <chain> <rule definition>

table [family] <name> (shortcut for `add table`)

insert
  rule [family] <table> <chain> <rule definition>

delete
  table [family] <name>
  chain [family] <table> <name>
  rule [family] <table> <handle>

flush
  table [family] <name>
  chain [family] <table> <name>
 */

{
	/*
		This block is for predefines global to the parser
	*/
	var nft = require('./nftables.js');
	var cmn = require('../libs/common.js');
	var bignum = require('bignum');
	var structs = require('./nfstructs.js');
	var debug = cmn.logger.debug;
	var util = require('util');

	var payload_len = 0;
	var expressions_array = [];

	var command_object = {};
	command_object.params = {};
	command_object.family = "ip"; // default when not specified

	var or_values = function(values) {
		var v = values || [], ret = 0;
		v.forEach(function(num) { ret = ret | num; } );
		return ret;
	}
}

start
	= command:command { return command_object; }

command
	= op:operation { }

operation
	=   "list" 		_   family? 		list_entity		{ command_object.command = "list"; return null;}
	/ 	"add" 		_	family? 		add_entity		{ command_object.command = "add"; }
	/ 	"table"		_	family? 		addtable_entity	{ command_object.command = "add"; }
	/ 	"insert"	_ 	family? 		insert_entity	{ command_object.command = "insert"; }
	/ 	"delete"	_	family? 		delete_entity	{ command_object.command = "delete"; }
	/ 	"flush" 	_	family? 		flush_entity	{ command_object.command = "flush"; }
	/  	"monitor"  	{ command_object.command = "monitor"; }

list_entity
	= "table" !"s" _ table_name
		{ command_object.type = "table"; }

	/ "tables"
		{ command_object.type = "table"; }

	/ "chain" !"s" _ chain_specifier
		{ command_object.type = "chain"; }

	/ "chains" __ table_identifier?
		{ command_object.type = "chain"; }

	/ "rule" !"s" __ rule_specifier
		{ command_object.type = "rule"; }

	/ "rules"__ table_identifier __ chain_identifier
		{ command_object.type = "rule"; }

	/ "set" _ set_name
		{ command_object.type = "set"; }

	/ "elements" _ table_identifier _ set_name
		{ 
			command_object.type = "set"; 
			command_object.params.id = 1; 
		}

add_entity
	= "table" _ table_name
		{ command_object.type = "table"; }

	/ "chain" _ table_identifier _ chain_name _ hook_expression
		{ command_object.type = "chain"; }

	/ "rule" _ table_identifier _ chain_identifier _ rule_expression
		{ command_object.type = "rule"; }

	/ "set" _ table_identifier _ set_name _ settype_expression
		{ command_object.type = "set"; }

	/ "element" _ set_identifier _ element_expression
		{ command_object.type = "setelem"; }

addtable_entity
	= table_name
		{ command_object.type = "table"; }

insert_entity
	= "rule" _ table_identifier _ chain_identifier _ rule_position _ rule_expression
		{ command_object.type = "rule"; }

delete_entity
	= "table" _ table_name
		{ command_object.type = "table"; }

	/ "chain" _ table_identifier _ chain_name
		{ command_object.type = "chain"; }

	/ "rule" _ table_identifier _ chain_identifier _ rule_handle
		{ command_object.type = "rule"; }

	/ "element" _ set_identifier _ element_expression
		{ command_object.type = "setelemlist"; }

flush_entity
	= "table" _ table_name
		{ command_object.type = "table"; }

	/ "chain" _ table_identifier _ chain_name
		{ command_object.type = "chain"; }

	/ "ruleset"
		{ command_object.type = "ruleset"; }
	
family
	= family:("ip" "6"?) __
		{
			command_object.family = family.join("");
		}

chain_name
	= ch:chain { command_object.params.name = ch; }

chain_identifier
	= ch:chain { command_object.params.chain = ch; }

table_name
	= ta:table { command_object.params.name = ta; }

table_identifier
	= ta:table { command_object.params.table = ta; }

chain_specifier
	= __ table_identifier __ chain_name

rule_specifier
	= __ table_identifier __ chain_identifier?

set_name
	= st:set { command_object.params.name = st; }

set_identifier
	= ti:table _ st:set
		{ command_object.params.table = ti; command_object.params.set = st; }

rule_expression
	= rd:rule_definition? meta:meta_stmt* ct:connection_track* lgst:log_stmt? nat:nat_expr? misc:rule_misc? act:rule_action? 
		{

			var exprs = [];

			if(expressions_array != undefined) {
				exprs = expressions_array;
			}

			if(ct != undefined) {
				ct.forEach(function(connection_track) {
					for(var elem in connection_track) {
						exprs.push(connection_track[elem]);
					}
				});
			}
			if(meta != undefined) {
				meta.forEach(function(m){
					for(var elem in m) {
						exprs.push(m[elem])
					}
				});
			}
			if(lgst != undefined) exprs.push(lgst);
			if(nat != undefined) {
				nat.forEach(function(n){
					exprs.push(n)
				});
			}
			if(misc != undefined) exprs.push(misc);
			if(act != undefined) exprs.push(act);

			command_object.params.expressions = exprs;
		}

table
	= ta:string_label
		{
			return ta.join("");
		}

chain
	= chain:string_label
		{
			return chain.join("");
		}

set
	= set:string_label
		{
			return set.join("");
		}

string_label
	= [-_0-9a-zA-Z]+

rule_handle
	= "handle" _ rh:( hex / decimal )
		{
			var hndl = rh.toBuffer({endian: 'big', size: 8});
			command_object.params.handle = '0x' + hndl.toString('hex');
		}

rule_action
	= ra:(drop / accept) __
		{
			return(ra);
		}

nat_expr
	= ty:("dnat" / "snat") _ na:nat_address np:nat_port?
		{
			debug('nat_expr');
			return structs.build_nat_expression(ty, na, np, command_object.family);
		}

nat_address
	= na:(octets / quads)
		{
			return na;
		}

nat_port
	= ":" np:[0-9]+
		{
			return np.join("");
		}

rule_misc
	= rm:(counter)

rule_position
	= "position" _ p:( hex / decimal )
		{
			var pos = p.toBuffer({endian: 'big', size: 8});
			command_object.params.position = '0x' + pos.toString('hex');
		}

rule_definition
	= ctr:(rule_criteria)+

rule_criteria
	= rps:rule_packet_selector _ pfv:ip_packet_field_value __

rule_packet_selector
	= pt:packet_type
		{ debug("packet_selector");
			expressions_array = expressions_array.concat(structs.build_packet_selector(pt))
	        payload_len = pt.len; // remeber last payload load for make the compare value
		}

packet_type
	= pkt:tcp  _ fld:tcp_field { fld.payload_base = pkt; return fld; }
	/ pkt:ip   _ fld:ip_field  { fld.payload_base = pkt; return fld; }
	/ pkt:ip6  _ fld:ip6_field { fld.payload_base = pkt; return fld; }
	/ pkt:udp  _ fld:udp_field { fld.payload_base = pkt; return fld; }
	/ pkt:icmpv6  _ fld:icmpv6_field { fld.payload_base = pkt; return fld; }

//  packet type bases
tcp
	= "tcp"
		{
			expressions_array = expressions_array.concat(structs.build_protocol('0x06'));
			return nft.nft_payload_bases.NFT_PAYLOAD_TRANSPORT_HEADER;
		}

udp
	= "udp"
		{
			expressions_array = expressions_array.concat(structs.build_protocol('0x11'));
			return nft.nft_payload_bases.NFT_PAYLOAD_TRANSPORT_HEADER;
		}

icmpv6
	= "icmpv6"
		{
			expressions_array = expressions_array.concat(structs.build_protocol_ip6('0x3A'));
			return nft.nft_payload_bases.NFT_PAYLOAD_NETWORK_HEADER;
		}

ip
	= "ip" !"6" 
		{ 
			return nft.nft_payload_bases.NFT_PAYLOAD_NETWORK_HEADER; 
		}

ip6
	= "ip6"  
		{ 
			return nft.nft_payload_bases.NFT_PAYLOAD_NETWORK_HEADER; 
		}


/*
	Packet field definitions

  	// Commented out fields are combined into the upper and
  	// lower portion of a field and not supported yet.
*/
tcp_field
	= "sport" { return { offset: nft.tcphdr_offsets.source, len: nft.tcphdr_sizes.source }; }
	/ "dport" { return { offset: nft.tcphdr_offsets.dest, len: nft.tcphdr_sizes.dest }; }
	/ "sequence" { return { offset: nft.tcphdr_offsets.seq, len: nft.tcphdr_sizes.seq }; }
	/ "ackseq" { return { offset: nft.tcphdr_offsets.ack_seq, len: nft.tcphdr_sizes.ack_seq }; }
//	/ "doff" { return { offset: nft.tcphdr_offsets.offset_flag, len: nft.tcphdr_sizes.offset_flag }; }
	/ "flags" { return { offset: nft.tcphdr_offsets.offset_flag, len: nft.tcphdr_sizes.offset_flag }; }
	/ "window" { return { offset: nft.tcphdr_offsets.window, len: nft.tcphdr_sizes.window }; }
	/ "checksum" { return { offset: nft.tcphdr_offsets.check, len: nft.tcphdr_sizes.check }; }
	/ "urgptr" { return { offset: nft.tcphdr_offsets.urg_ptr, len: nft.tcphdr_sizes.urg_ptr }; }

ip_field
	= "version" { return { offset: nft.iphdr_offsets.version_ihl, len: nft.iphdr_sizes.version_ihl }; }
//	/ "hdrlength" { return { offset: nft.iphdr_offsets.tos, len: nft.iphdr_sizes.tos }; }
	/ "tos" { return { offset: nft.iphdr_offsets.tos, len: nft.iphdr_sizes.tos }; }
	/ "length" { return { offset: nft.iphdr_offsets.tot_len, len: nft.iphdr_sizes.tot_len }; }
	/ "id" { return { offset: nft.iphdr_offsets.id, len: nft.iphdr_sizes.id }; }
	/ "frag-off" { return { offset: nft.iphdr_offsets.frag_off, len: nft.iphdr_sizes.frag_off }; }
	/ "ttl" { return { offset: nft.iphdr_offsets.ttl, len: nft.iphdr_sizes.ttl }; }
	/ "protocol" { return { offset: nft.iphdr_offsets.protocol, len: nft.iphdr_sizes.protocol }; }
//	/ "checksum" { return { offset: nft.iphdr_offsets.protocol, len: nft.iphdr_sizes.protocol }; }
	/ "saddr" { return { offset: nft.iphdr_offsets.saddr, len: nft.iphdr_sizes.saddr }; }
	/ "daddr" { return { offset: nft.iphdr_offsets.daddr, len: nft.iphdr_sizes.daddr }; }

ip6_field
	= "version" { return { offset: nft.ipv6hdr_offsets.prio_version, len: nft.ipv6hdr_sizes.prio_version };	}
//	/ "priority" { return { offset: nft.ipv6hdr_offsets.prio_version, len: nft.ipv6hdr_sizes.prio_version };	}
	/ "flowlabel" { return { offset: nft.ipv6hdr_offsets.flow_lbl, len: nft.ipv6hdr_sizes.flow_lbl };	}
	/ "length" { return { offset: nft.ipv6hdr_offsets.payload_len, len: nft.ipv6hdr_sizes.payload_len };	}
	/ "nexthdr" { return { offset: nft.ipv6hdr_offsets.nexthdr, len: nft.ipv6hdr_sizes.nexthdr };	}
	/ "hoplimit" { return { offset: nft.ipv6hdr_offsets.saddr, len: nft.ipv6hdr_sizes.saddr };	}
	/ "saddr" { return { offset: nft.ipv6hdr_offsets.saddr, len: nft.ipv6hdr_sizes.saddr };	}
	/ "daddr" { return { offset: nft.ipv6hdr_offsets.daddr, len: nft.ipv6hdr_sizes.daddr };	}

udp_field
	= "sport" { return { offset: nft.udphdr_offsets.source, len: nft.udthdr_sizes.source };	}
	/ "dport" { return { offset: nft.udphdr_offsets.dest, len: nft.udphdr_sizes.dest };	}
	/ "length" { return { offset: nft.udphdr_offsets.dest, len: nft.udphdr_sizes.len };	}
	/ "checksum" { return { offset: nft.udphdr_offsets.check, len: nft.udphdr_sizes.check }; }

icmpv6_field
	= "type" { return { offset: nft.ipv6hdr_offsets.nexthdr, len: nft.ipv6hdr_sizes.nexthdr }; }

ip_packet_field_value
	= pv:icmp6_type_field_value { return pv; }
	/ nm:number { return nm; }
	/ ad:ipaddress { return ad; }
	/ other:([a-z]*) { throw new Error("Only numeric field types currently supported"); }

icmp6_type_field_value
	= "destination-unreachable" { expressions_array.push(structs.build_icmp6_type(0x76)); }
	/ "packet-too-big"   		{ expressions_array.push(structs.build_icmp6_type(0x77)); }
	/ "time-exceeded"			{ expressions_array.push(structs.build_icmp6_type(0x78)); }
	/ "param-problem"			{ expressions_array.push(structs.build_icmp6_type(0x79)); }		
	/ "echo-request"			{ expressions_array.push(structs.build_icmp6_type(0x80)); }
	/ "echo-reply"				{ expressions_array.push(structs.build_icmp6_type(0x81)); }
	/ "mld-listener-query"		{ expressions_array.push(structs.build_icmp6_type(0x82)); }
	/ "mld-listener-report"		{ expressions_array.push(structs.build_icmp6_type(0x83)); }
	/ "mld-listener-reduction"	{ expressions_array.push(structs.build_icmp6_type(0x84)); }
	/ "nd-router-solicit"		{ expressions_array.push(structs.build_icmp6_type(0x85)); }
	/ "nd-router-advert"		{ expressions_array.push(structs.build_icmp6_type(0x86)); }
	/ "nd-neighbor-solicit"		{ expressions_array.push(structs.build_icmp6_type(0x87)); }
	/ "nd-neighbor-advert"		{ expressions_array.push(structs.build_icmp6_type(0x88)); }
	/ "nd-redirect"				{ expressions_array.push(structs.build_icmp6_type(0x89)); }
	/ "router-renumbering"		{ expressions_array.push(structs.build_icmp6_type(0x90)); }

ipaddress
	= ipa:(ipv4address / ipv6address)
	{
		debug("ipaddress");
		return ipa;
	}

ipv6address
	= ipv6addr cidr? _

ipv4address
	= ipv4addr cidr? _

number
	= num:(hex / decimal) !("."/"::") _
		{debug("number");
			var prepend = "";
			var numstr = num.toString(16);
			var pad = payload_len * 2;
			while(numstr.length < pad) numstr = "0".concat(numstr);
			numstr = '0x' + numstr;

			expressions_array.push(
	        {
	            elem:
	            {
					name: "cmp",
					data: {
						SREG: 		nft.nft_registers.NFT_REG_1,
						OP: 		nft.nft_cmp_ops.NFT_CMP_EQ,
						DATA: 		{ VALUE: numstr } // 0x0016 = 22 - ssh protocol
	                }
				}
			});
		}

ipv6addr
	= quads:quads
		{ debug("ipv6addr");
			if(command_object.family !== 'ip6') throw new Error("family != ip6 when ipv6 address specified")

			expressions_array.push(
			{
	            elem:
	            {
					name: "cmp",
					data: {
						SREG: 		nft.nft_registers.NFT_REG_1,
						OP: 		nft.nft_cmp_ops.NFT_CMP_EQ,
						DATA: 		{
										// overkill but throws for bad hex val
										VALUE: "0x" + quads
									} // C0A83800 = 192.168.56.0
	                }
				}
			});
		}

ipv4addr
	= octets:octets
		{  debug("ipv4addr");
			if(command_object.family !== 'ip') throw new Error("family != ip when ip address specified")

			expressions_array.push(
			{
	            elem:
	            {
					name: "cmp",
					data: {
						SREG: 		nft.nft_registers.NFT_REG_1,
						OP: 		nft.nft_cmp_ops.NFT_CMP_EQ,
						DATA: 		{
										// overkill but throws for bad hex val
										VALUE: "0x" + octets
									} // C0A83800 = 192.168.56.0
	                }
				}
			});
		}

cidr
	= cidr:(ipv4cidr / ipv6cidr)
		{   debug("cidr")
			var last_addr = expressions_array.pop();
			expressions_array.push(
			{
	            elem:
	            {
					name: "bitwise",
					data: {
						SREG: 		nft.nft_registers.NFT_REG_1,
						DREG:		nft.nft_registers.NFT_REG_1,
						LEN: 		cidr.len,
						MASK: 		{ VALUE: "0x" + cidr.val },
						XOR: 		{ VALUE: "0x00000000" }
	                }
				}
			});
			expressions_array.push(last_addr);
		}


drop
	= "drop"
		{
	        return(
	        {
	            elem:
	            {
					name: "immediate",
					data: {
						DREG: 		nft.nft_registers.NFT_REG_VERDICT,
						DATA: 		{ VERDICT: { CODE: 0x00000000 } }
	                }
				}
			});
		}

accept
	= "accept"
		{
	        return(
	        {
	            elem:
	            {
					name: "immediate",
					data: {
						DREG: 		nft.nft_registers.NFT_REG_VERDICT,
						DATA: 		{ VERDICT: { CODE: 0x00000001 } }
	                }
				}
			});
		}

counter
	= "counter" __
		{
	        return(
	        {
	            elem:
	            {
					name: "counter"
				}
			});
		}

////////////////////////////////////////////////////////////////////////////
// Sets
settype_expression
	= "{" __ "type" __ st:set_type __ "}"
		{
			command_object.params.set 
			command_object.params.flags = 0;
			command_object.params.keytype = st.skt;
			command_object.params.keylen = st.skl;
			command_object.params.id = 1; //sid;
		}

set_type
	= "ipv4_addr" 	{ return { skt: 7, skl: 4 }; }
	/ "ipv6_addr" 	{ return { skt: 8, skl: 16 }; }
	/ "ether_addr" 	{ return { skt: 9, skl: 6 }; }
	/ "inet_proto" 	{ return { skt: 12, skl: 1 }; }
	/ "inet_service" 	{ return { skt: 13, skl: 2 }; }
	/ "mark" 			{ return { skt: 19, skl: 4 }; }

set_id
	= "id" _ d:decimal
		{ return d.toNumber(); }

element_expression
	= "{" __ el:ipv4addr_element __ "}"
	{
		command_object.params.elements = el;
	}


ipv4addr_element
	= ","? __ octets:octets
		{  debug("ipv4addr");
			if(command_object.family !== 'ip') throw new Error("family != ip when ip address specified")

			return {
	            key: {
	            	key: {
						value: "0x" + octets
	            	}
				}
			};
		}


////////////////////////////////////////////////////////////////////////////
hook_expression          //{ type filter hook input priority 0 }
	= "{" __ "type" _ ht:hooktype _ "hook" _ hn:hooknum _ "priority" _ hp:hookprio __ "}"
		{
			command_object.params.hook = {};
			command_object.params.type = ht;
			command_object.params.hook.hooknum = hn;
			command_object.params.hook.priority = hp;
		}

hooktype
	= "filter" / "route" / "nat"

hooknum
	= 	"prerouting"  	{ return 0; }
	/	"input" 		{ return 1; }
	/	"forward" 		{ return 2; }
	/	"output" 		{ return 3; }
	/	"postrouting"	{ return 4; }

hookprio
	= sg:"-"? pr:([0-9]+) { var ret = (sg) ? sg : ""; ret += pr.join(""); return ret; }

// nftables/src/ct.c
nft_ct_key
	= "state" 		_ 	state:ct_states*	_ 	{ return { key:0, value:or_values(state)  }; }
	/ "direction" 	_ 	dir:ct_direction  	_ 	{ return { key:1, value:dir }; }
	/ "status"		_ 	status:ct_status*	_	{ return { key:2, value:or_values(status) }; }
	/ "mark"		_   mark:ct_mark		_   { return { key:3, value:mark }; }
	/ "secmark"							{ return { key:4, value:dir }; }
	/ "expiration"						{ return { key:5, value:dir }; }
	/ "helper"							{ return { key:6, value:dir }; }
	/ "l3protocol"						{ return { key:7, value:dir }; }
	/ "src"								{ return { key:8, value:dir }; }
	/ "dst"								{ return { key:9, value:dir }; }
	/ "protocol"						{ return { key:10, value:dir }; }
	/ "proto_src"						{ return { key:11, value:dir }; }
	/ "proto_dst"						{ return { key:12, value:dir }; }
	/ "labels"							{ return { key:13, value:dir }; }

ct_states
	= ","? st:ct_state {return st;}

ct_state
	= "established"					 	{ return 0x02; }
	/ "related"							{ return 0x04; }
	/ "new"								{ return 0x08; }
	/ "invalid"							{ return 0x01; }

ct_direction
	= "original"	{ return 0; }
	/ "reply"		{ return 1; }

// There are more, but most of them don't make sense fo filtering
ct_status
	= "expected" 	{ return 0x001; }
	/ "seen-reply" 	{ return 0x002; }
	/ "assured" 	{ return 0x004; }
	/ "confirmed" 	{ return 0x008; }
	/ "snat" 		{ return 0x010; }
	/ "dnat" 		{ return 0x020; }
	/ "dying" 		{ return 0x200; }

ct_mark
	= decimal

// see: include/linux/netfilter/nf_conntrack_common
connection_track
	= "ct" _ op:nft_ct_key
		{
			var mask = new Buffer(4);
			mask.fill(0);
			mask.writeUInt16LE(op.value);
	        var retval = [
	            {
	            elem:
	            {
					name: "ct",
					data: {
						KEY: 		op.key, //op.key,
						//DIRECTION: 	1, //op.state,
						//SREG:      	1
						DREG:       1
	                }
				}},

				{
	            elem:
	            {
					name: "bitwise",
					data: {
						SREG: 		nft.nft_registers.NFT_REG_1,
						DREG:		nft.nft_registers.NFT_REG_1,
						LEN: 		4,
						MASK: 		{ VALUE: "0x" + mask.toString('hex') },
						XOR: 		{ VALUE: "0x00000000" }
	                }
				}},

				{
	            elem:
	            {
					name: "cmp",
					data: {
						SREG: 		nft.nft_registers.NFT_REG_1,
						OP:			nft.nft_cmp_ops.NFT_CMP_NEQ,
						DATA: 		{ VALUE: "0x00000000" }
	                }
				}}

			];

			// DREG: 		0,
			// DIRECTION: 	2,
			// SREG: 		3,
			// if(pfx != null) retval.elem.data.PREFIX = pfx;

			return retval;
		}

log_stmt
	= "log" __ pfx:log_prefix? __ grp:log_group? __ snp:log_snaplen?
			__ thr:log_qthreshold? __ lvl:log_level? __ flgs:log_flags? __
		{
	        var retval = {
	            elem:
	            {
					name: "log",
					data: {
						GROUP: 		(grp === null) ? 0 : grp,
	                }
				}
			};

			if(pfx != null) retval.elem.data.PREFIX = pfx;
			if(snp != null) retval.elem.data.SNAPLEN = snp;
			if(thr != null) retval.elem.data.QTHRESHOLD = thr;
			if(lvl != null) retval.elem.data.LEVEL = lvl;
			if(flgs != null) retval.elem.data.FLAGS = flgs;

			return retval;
		}

log_prefix
	= "prefix" _ '"'str:string'"'
		{ return str; }

log_group
	= "group" _ d:decimal
		{ return d.toNumber(); }

log_snaplen
	= "snaplen" _ d:decimal
		{ return d.toNumber(); }

log_qthreshold
	= "qthreshold" _ d:decimal
		{ return d.toNumber(); }

log_level
	= "level" _ d:decimal
		{ return d.toNumber(); }

log_flags
	= "flags" _ d:decimal
		{ return d.toNumber(); }

meta_stmt
	= "meta" _ mp:meta_params __ me:mac_expression? __
		{
			if(me != null) mp = mp.concat(me); return mp; 
		}

meta_params
	// see netfilter/nftables/src/meta.c line:363
	= "len" _ val:decimal
		{ return structs.build_meta_integer(nft.nft_meta_keys.LEN, val, 4); }
	/ "protocol" _ val:ether_type
		{ return structs.build_meta_integer(nft.nft_meta_keys.PROTOCOL, val, 2); }
	/ "priority" _ s:"set"?__ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.PRIORITY, val, 4, s); }
	/ "mark" _ s:"set"?__ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.MARK, val, 4, s); }
	/ "iif" _ val:(interface_to_index)
		{ return structs.build_meta_integer(nft.nft_meta_keys.IIF, val, 4); }
	/ "oif" _ val:(interface_to_index)
		{ return structs.build_meta_integer(nft.nft_meta_keys.OIF, val, 4); }
	/ "iifname" _ val:(string)
		{ return structs.build_meta_string(nft.nft_meta_keys.IIFNAME, val, 14); }
	/ "oifname" _ val:(string)
		{ return structs.build_meta_string(nft.nft_meta_keys.OIFNAME, val, 14); }
	/ "iiftype" _ val:ether_type
		{ return structs.build_meta_integer(nft.nft_meta_keys.IIFTYPE, val, 2); }
	/ "oiftype" _ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.OIFTYPE, val, 2); }
	/ "skuid" _ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.SKUID, val, 4); }
	/ "skgid" _ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.SKGID, val, 4); }
//	/ "nftrace" _ val:(hex / decimal)
	/ "rtclassid" _ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.RTCLASSID, val, 4); }
//	/ "secmark" _ val:(hex / decimal)
	/ "nfproto" _ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.NFPROTO, val, 1); }
	/ "l4proto" _ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.L4PROTO, val, 1); }
	/ "bri_iifname" _ val:(hex / decimal)
		{ return structs.build_meta_string(nft.nft_meta_keys.BRI_IIFNAME, val, 14); }
	/ "bri_oifname" _ val:(hex / decimal)
		{ return structs.build_meta_string(nft.nft_meta_keys.BRI_OIFNAME, val, 14); }
	/ "pkttype" _ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.PKTYPE, val, 1); }
	/ "cpu" _ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.CPU, val, 4); }
	/ "iifgroup" _ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.IIFGROUP, val, 4); }
	/ "oifgroup" _ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.OIFGROUP, val, 4); }
	/ "cgroup" _ val:(hex / decimal)
		{ return structs.build_meta_integer(nft.nft_meta_keys.CGROUP, val, 4); }

interface_to_index
	= name:idstring __
		{
			var index = cmn.nativelib.ifNameToIndex(name);
			if(util.isError(index)) {
				error(util.inspect(index));
				throw(index);
			} else {
				return index;
			}
		}

// include/uapi/linux/if_ether.h
ether_type
	= "ip" !"6" { return "0x0800"; }
	/ "arp"	{ return "0x0806"; }
	/ "ip6" { return "0x86DD"; }
	/ "vlan"{ return "0x8100"; }
	/ "ether"{ return "0x001"; }

mac_expression
	= ma:mac_address
		{
			return structs.build_mac_payload(ma);
		}

mac_address
	= ma:([0-9a-fA-F][0-9a-fA-F]":"[0-9a-fA-F][0-9a-fA-F]":"[0-9a-fA-F][0-9a-fA-F]":"[0-9a-fA-F][0-9a-fA-F]":"[0-9a-fA-F][0-9a-fA-F]":"[0-9a-fA-F][0-9a-fA-F])
		{
			var ret = ma.join("");
			ret = ret.split(':').join("");
			return(ret);
		}

ipv6cidr
	= "/" cd:([0-9][0-9]?[0-9]?)
		{
			var cidrv  = parseInt(cd.join(""), 10);
			return {
				val: cmn.maskFromCidr(cidrv, 'inet6'),
				len: 16
			};
		}

ipv4cidr
	= "/" cd:([0-9][0-9]?)
		{
			var cidrv  = parseInt(cd.join(""), 10);
			return {
				val: cmn.maskFromCidr(cidrv, 'inet'),
				len: 4
			};
		}

octets
	= oct1:([0-9]+) "." oct2:([0-9]+) "." oct3:([0-9]+) "." oct4:([0-9]+)
		{
			var addr = new Buffer(4);
			var octets = [ oct1.join(""), oct2.join(""), oct3.join(""), oct4.join("") ];
			addr.writeUInt8( parseInt(octets[0], 10), 0);
			addr.writeUInt8( parseInt(octets[1], 10), 1);
			addr.writeUInt8( parseInt(octets[2], 10), 2);
			addr.writeUInt8( parseInt(octets[3], 10), 3);

			return addr.toString('hex');
		}

quads
	= st:startquad? nx:nextequad*
		{
			var buf = new Buffer(16);
			buf.fill(0);
			var sindex = 0;
			var written = 0;

			if(st != undefined) {
				var val = parseInt(st, 16);
				buf.writeUInt16BE(val, sindex, 2);
				written++;
				sindex += 2;
			}

			for(var i = 0; i < nx.length; i++) {
				if(nx[i].skip == true) {
					sindex = (8 - (nx.length - written + 1)) * 2;
				}
				val = parseInt(nx[i].val, 16);
				buf.writeUInt16BE(val, sindex, 2);
				sindex += 2;
				written++;
			}

			return buf.toString('hex');
		}

startquad
	= q:([0-9a-fA-F]+) { val: return q.join(""); }

nextequad
	= q:(contquad / skipequad) { return q; }

contquad
	= ":"  q:[0-9a-fA-F]+ { return { skip: false, val: q.join("") }; }

skipequad
	= "::" q:[0-9a-fA-F]+ { return { skip: true, val: q.join("") }; }

hex
	= nibbles:("0x" [0-9a-fA-F]+) { return bignum(nibbles[1].join(""), 16); }

decimal
	= digits:[0-9]+ { return bignum(digits.join(""), 10); }

string
	= str:([ 0-9a-zA-Z])+ { return str.join(""); }

idstring
	= str:([0-9a-zA-Z])+ { return str.join(""); }
_
	= ([ \t])+

__
	= ([ \t])*
