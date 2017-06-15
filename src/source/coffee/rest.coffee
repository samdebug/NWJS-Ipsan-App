class Rest
    constructor: (@host) ->
    ajax: (type, url, data) =>
        $.ajax
            headers: Accept : "application/json"
            type: type
            url: "http://#{@host}#{url}"
            data: data

    get: (url, data) =>
        @ajax "get", url, data

    _delete: (url, data) =>
        @ajax "delete", url, data

    post: (url, data) =>
        @ajax "post", url, data

    put: (url, data) =>
        @ajax "put", url, data

class ResRest extends Rest
    constructor: (@host, @res) ->
    list: () =>
        @get "/api/#{@res}"

    create: (params) =>
        @post "/api/#{@res}", params

    delete: (id) =>
        @_delete "/api/#{@res}/#{id}"

class DiskRest extends Rest
    list: () =>
        @get "/api/disks"

    format: (location) =>                 #格式化
        @put "/api/disks/#{location}", host: 'native'

    set_disk_role: (location, role, raidname) =>             #为磁盘设定角色
        data = role: role
        if raidname isnt null
            data.raid = raidname
        @put "/api/disks/#{location}", data

class RaidRest extends ResRest
    constructor: (host) ->
        super host, 'raids'

class VolumeRest extends ResRest
    constructor: (host) ->
        super host, 'volumes'

class InitiatorRest extends ResRest
    constructor: (host) ->
        super host, 'initiators'

    map: (wwn, volume) =>
        @post "/api/#{@res}/#{wwn}/luns", volume: volume

    unmap: (wwn, volume) =>
        @delete "#{wwn}/luns/#{volume}"

class DSURest extends Rest
    list: () =>
        @get "/api/dsus"
    
    slient: () =>
        @put "/api/beep"
        
class NetworkRest extends Rest
    ajax: (type, url, data) =>
        $.ajax
            headers: Accept : "application/json"
            type: type
            url: "http://#{@host}#{url}"
            data: data
            timeout: 6000

    list: () =>
        @get "/api/interfaces"
    
    config: (iface, ipaddr, netmask) =>
        @put "/api/network/interfaces/#{iface}", address:ipaddr, netmask:netmask

    create_eth_bonding: (ip, netmask, mode) =>
        @post "/api/network/bond/bond0",
            slaves: "eth0,eth1"
            address: ip
            netmask: netmask
            mode: mode

    modify_eth_bonding: (ip, netmask)=>
        @put "/api/network/bond/bond0", address: ip, netmask: netmask

    cancel_eth_bonding: =>
        @_delete "/api/network/bond/bond0"

class JournalRest extends Rest
    list: (offset, limit) =>
        @get "/api/journals", offset:offset, limit:limit

class UserRest extends Rest
    change_password: (name, old_password, new_password) =>
        @put "/api/users/#{name}/password", old_password: old_password, new_password: new_password

class ZnvConfigRest extends Rest
    precreate: (volume) =>
        @post "/api/precreate", volume: volume
        
    znvconfig: (bool,serverid, local_serverip, local_serverport, cmssverip, cmssverport, directory) =>
        if bool
            @put "/api/zxconfig/store/set",serverid: serverid,local_serverip: local_serverip,local_serverport: local_serverport,cmssverip: cmssverip,cmssverport: cmssverport,directory: directory
        else
            @put "/api/zxconfig/dispath/set",serverid: serverid,local_serverip: local_serverip,local_serverport: local_serverport,cmssverip: cmssverip,cmssverport: cmssverport

    start_service: (bool) =>
        if bool
            @put "/api/zxconfig/store/start"
        else
            @put "/api/zxconfig/dispath/start"

    stop_service: (bool) =>
        if bool
            @put "/api/zxconfig/store/stop"
        else
            @put "/api/zxconfig/dispath/stop"


class CommandRest extends Rest
    ajax: (type, url, data) =>
        $.ajax
            headers: Accept : "application/json"
            type: type
            url: "http://#{@host}#{url}"
            data: data
            timeout: 4000

    poweroff: () =>
        @put "/api/commands/poweroff"

    reboot: () =>
        @put "/api/commands/reboot"

    sysinit: () =>
        @put "/api/commands/init"
        
    recover: () =>
        @put "/api/commands/recovery"        

    create_lw_files: () =>
        @put "/api/commands/create_lw_files", async: true

    slient: () =>
        @put "/api/beep"
        
class GatewayRest extends Rest
    query: () =>
        @get "/api/network/gateway"

    config: (address) =>
        @put "/api/network/gateway", address: address

class SystemInfoRest extends Rest
    query: () =>
        @get "/api/systeminfo"

class SessionRest extends Rest
    ajax: (type, url, data) =>
        $.ajax
            headers: Accept : "application/json"
            type: type
            url: "http://#{@host}#{url}"
            data: data
            timeout: 4000

    create: (name, passwd) =>
        @post "/api/sessions", name: name, password: passwd

class FileSystemRest extends Rest
    ajax: (type, url, data) =>
        $.ajax
            headers: Accept : "application/json"
            type: type
            url: "http://#{@host}#{url}"
            data: data
            timeout: 300 * 1000

    query: () =>
        @get "/api/filesystems"

    create_cy: (name, volume) =>
        @post "/api/filesystems", name:name, volume:volume
        
    create: (name, type, volume) =>
        @post "/api/filesystems", name:name, type:type, volume:volume
        
    delete: (name) =>
        @_delete "/api/filesystems/#{name}"

    scan: (name) =>
        @put "/api/filesystems/detection", name:name
        
class MonFSRest extends Rest
    query: () =>
        @get "/api/monfs"

    create: (name, volume) =>
        @post "/api/monfs", name:name, volume:volume

    delete: (name) =>
        @_delete "/api/monfs/#{name}"

class IfacesRest extends Rest
    ajax: (type, url, data) =>
        $.ajax
            headers: Accept : "application/json"
            type: type
            url: "http://#{@host}#{url}"
            data: data
            timeout: 2000
            
    query: () =>
        @get "/api/ifaces"


class SyncConfigRest extends Rest
    ajax: (type, url, data) =>
        $.ajax
            headers: Accept : "application/json"
            type: type
            url: "http://#{@host}#{url}"
            data: data
            timeout: 400000

    sync_enable: (name) =>
        @put "/api/sync", name: name, command: "start"  
                                
    sync_disable: (name) =>
        console.log name
        @put "/api/sync", name: name, command: "stop"  
              
this.DSURest = DSURest
this.DiskRest = DiskRest
this.RaidRest = RaidRest
this.VolumeRest = VolumeRest
this.InitiatorRest = InitiatorRest
this.UserRest = UserRest
this.NetworkRest =  NetworkRest
this.JournalRest = JournalRest
this.CommandRest = CommandRest
this.GatewayRest = GatewayRest
this.SystemInfoRest = SystemInfoRest
this.SessionRest = SessionRest
this.MonFSRest = MonFSRest
this.IfacesRest = IfacesRest
this.FileSystemRest = FileSystemRest
this.ZnvConfigRest = ZnvConfigRest
this.SyncConfigRest = SyncConfigRest