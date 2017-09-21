class ResSource
    constructor: (@rest, @process) ->
        @items = []
        @map   = {}

    update: () =>
        @rest.list().done (data) =>
            if data.status == "success"
                @_update_data data.detail
            else
                @_update_data []
        .fail (jqXHR, text_status, e) =>
            @_update_data []

    get: (id) => @map[id]

    _update_data: (data) =>
        if @process
            data = @process(data)
        @items = data
        @map = {}
        for o in @items
            @map[o.id] = o
        @notify_updated()

    notify_updated: () =>
        $(this).triggerHandler "updated", this

class SingleSource
    constructor: (@rest, @default) ->
        @data = @default

    update: () =>
        @rest.query().done (data) =>
            if data.status == "success"
                @data = data.detail
            else
                @data = @default
            @notify_updated()
        .fail (jqXHR, text_status, e) =>
            @data = @default
            @notify_updated()

    notify_updated: () =>
        $(this).triggerHandler "updated", this

class Chain
    constructor: (@errc) ->
        @dfd = $.Deferred()
        @chains = []
        @total = 0

    chain: (arg) =>
        if arg instanceof Chain
            queue = arg.chains
        else if $.isArray arg
            queue = arg
        else
            queue = [arg]
        for step in queue
            @chains.push step
            @total += 1
        return this

    _notify_progress: () =>
        $(this).triggerHandler "progress", ratio: (@total-@chains.length)/@total

    _done: (data, text_status, jqXHR) =>
        if @chains.length == 0
            $(this).triggerHandler "completed"
            @dfd.resolve()
        else
            [@cur, @chains...] = @chains
            jqXHR = @cur()
            @_notify_progress()
            jqXHR.done(@_done).fail(@_fail)

    _fail: (jqXHR, text_status, e) =>
        reason = if jqXHR.status == 400 then JSON.parse(jqXHR.responseText) else text_status
        $(this).triggerHandler "error", error: reason, step: @cur
        if @errc
            @errc error: reason, step: @cur
            @_done()
        else
            @dfd.reject jqXHR.status, reason

    execute: () =>
        @_done()
        @promise = @dfd.promise()
        @promise

class StorageData
    constructor: (@host) ->
        @_update_queue = []
        @_deps =
           disks: ["disks", "raids", "journals"]
           raids: ["disks", "raids", "journals"]
           volumes: ["raids", "volumes", "initrs", "journals"]
           initrs: ["volumes", "initrs", "journals"]
           networks: ["networks", "gateway", "journals"]
           monfs: ["monfs", "volumes", "journals"]
           filesystem: ["filesystem", "volumes", "journals"]
           all: ["dsus", "disks", "raids", "volumes", "initrs", "networks", "journals", "gateway", "filesystem", "systeminfo"]

        @disks = new ResSource(new DiskRest(@host))
        @raids = new ResSource(new RaidRest(@host))
        @volumes = new ResSource(new VolumeRest(@host))
        @initrs = new ResSource(new InitiatorRest(@host))
        @networks = new ResSource(new NetworkRest(@host))
        @journals = new ResSource(new JournalRest(@host))
        @dsus = new ResSource(new DSURest(@host))

        @gateway = new SingleSource(new GatewayRest(@host), ipaddr: "")
        @monfs = new SingleSource(new MonFSRest(@host), {})
        @filesystem = new SingleSource(new FileSystemRest(@host), {})
        @systeminfo = new SingleSource(new SystemInfoRest(@host), version: "UNKOWN")

        @stats = items: []
        @socket_statist = io.connect "#{@host}/statistics", {
            "reconnect": false,
            "force new connection": true
        }
        @socket_statist.on "statistics", (data) =>               #get read_mb and write_mb
            if @stats.items.length > 120
                @stats.items.shift()
            @stats.items.push(data)
            $(@stats).triggerHandler "updated", @stats

        @socket_event = io.connect "#{@host}/event", {
            "reconnect": false,
            "force new connection": true
        }
        @socket_event.on "event", @feed_event
        @socket_event.on "disconnect", @disconnect_listener
        @_update_loop()


    raid_disks: (raid) =>
        disks = (d for d in @disks.items when d.raid == raid.name)
        disks.sort (o1,o2) -> o1.slot - o2.slot
        return disks

    volume_initrs: (volume) =>
        (initr for initr in @initrs.items when volume.name in (v for v in initr.volumes))

    initr_volumes: (initr) =>
        (v for v in @volumes.items when v.name in initr.volumes)

    spare_volumes: () =>
        used = []
        for initr in @initrs.items
            used = used.concat(initr.volumes)
        volume for volume in @volumes.items when volume.name not in used

    feed_event: (e) =>
        console.log e
        switch e.event
            when "disk.ioerror", "disk.formated", "disk.plugged", "disk.unplugged"
                @_update_queue.push @disks
                @_update_queue.push @journals
            when "disk.role_changed"
                @_update_queue.push @disks
                @_update_queue.push @raids
                @_update_queue.push @journals
            when "raid.normal", "raid.degraded", "raid.failed"
                @_update_queue.push @raids
                @_update_queue.push @journals
            when "raid.rebuild"
                raid = @raids.get e.raid
                if raid != undefined
                    raid.rebuilding = e.rebuilding
                    raid.health = e.health
                    raid.rebuild_progress = e.rebuild_progress
                    $(this).triggerHandler "raid", raid
            when "raid.rebuild_done"
                raid = @raids.get e.raid
                if raid != undefined
                    raid.rebuilding = e.rebuilding
                    raid.health = e.health
                    raid.rebuild_progress = e.rebuild_progress
                    $(this).triggerHandler "raid", raid
                    @_update_queue.push @disks
            when "raid.created", "raid.removed"           
                @_update_queue.push @disks
                @_update_queue.push @raids
                @_update_queue.push @journals
            when "raid.rqr"
                raid = @raids.get e.raid
                raid.rqr_count = e.rqr_count
                $(this).triggerHandler "raid", raid
            when "volume.failed", "volume.normal"
                volume = @volumes.get e.uuid
                if volume != undefined
                    volume.event = e.event
                    $(this).triggerHandler "volume", volume
                    @_update_queue.push @volumes
                    @_update_queue.push @journals
            when "volume.created"         
                @_update_queue.push @volumes
                @_update_queue.push @raids
                @_update_queue.push @journals
                volume = event : e.event
                $(this).triggerHandler "volume", volume
                #volume = sync:e.sync, sync_progress: e.sync_progress, id: e.uuid
                #$(this).triggerHandler "volume", volume
            when "volume.removed"
                @_update_queue.push @volumes
                @_update_queue.push @raids
                @_update_queue.push @journals
            when "volume.sync"
                volume = @volumes.get e.lun
                if volume != undefined
                    volume.sync_progress = e.sync_progress
                    volume.syncing = e.syncing
                    volume.event = e.event
                    $(this).triggerHandler "volume", volume
            when "volume.syncing"
                volume = @volumes.get e.lun
                if volume != undefined
                    volume.sync_progress = e.sync_progress
                    volume.syncing = e.syncing
                    volume.event = e.event
                    $(this).triggerHandler "volume", volume                
            when "volume.sync_done"
                volume = @volumes.get e.lun
                if volume != undefined
                    volume.sync_progress = e.sync_progress
                    volume.syncing = e.syncing
                    volume.event = e.event
                    $(this).triggerHandler "volume", volume
            when "initiator.created", "initiator.removed"
                @_update_queue.push @initrs
                @_update_queue.push @journals
            when "initiator.session_change"
                initr = @initrs.get e.initiator
                initr.active_session = e.session
                $(this).triggerHandler "initr", initr
            when "vi.mapped", "vi.unmapped"
                @_update_queue.push @initrs
                @_update_queue.push @volumes
                @_update_queue.push @journals
            when "monfs.created", "monfs.removed"
                @_update_queue.push @monfs
                @_update_queue.push @volumes
                @_update_queue.push @journals
            when "fs.created", "fs.removed"
                @_update_queue.push @filesystem
                @_update_queue.push @volumes
                @_update_queue.push @journals
            when "notification"
                $(this).triggerHandler "notification", e
            when "user.login"
                $(this).triggerHandler "user_login", e.login_id
            
    update: (res, errc) =>
        chain = new Chain errc
        chain.chain(($.map @_deps[res], (name) => (=> this[name].update())))
        chain

    _update_loop: =>
        @_looper_id = setInterval((=>
            @_update_queue = unique @_update_queue
            @_update_queue[0].update?() if @_update_queue[0]?
            @_update_queue = @_update_queue[1...]
            return
            ), 1000)

    close_socket: =>
        @socket_event.disconnect()
        @socket_statist.disconnect()
        clearInterval @_looper_id if @_looper_id?
        return

    disconnect_listener: =>
        $(this).triggerHandler "disconnect", @host

this.Chain = Chain
this.StorageData = StorageData
