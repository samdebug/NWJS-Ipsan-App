class Page extends AvalonTemplUI
    constructor: (prefix, src, attr={}) ->
        super prefix, src, ".page-content", true, attr

class DetailTablePage extends Page
    constructor: (prefix, src) ->
        super prefix, src

    detail: (e) =>
        if not @has_rendered
            return
        tr = $(e.target).parents("tr")[0]
        res = e.target.$vmodel.$model.e
        if @data_table.fnIsOpen tr
            $("div", $(tr).next()[0]).slideUp =>
                @data_table.fnClose tr
                res.detail_closed = true
                close_detial? res
                delete avalon.vmodels[res.id]
        else
            res.detail_closed = false
            [html,vm] = @detail_html res
            row = @data_table.fnOpen tr, html, "details"
            avalon.scan row, vm
            $("div", row).slideDown()

class OverviewPage extends Page
    constructor: (@sd, @switch_to_page) ->
        super "overviewpage-", "html/overviewpage.html"
        @flow_max = 0

        $(@sd.disks).on "updated", (e, source) =>
            disks = []
            
            for i in source.items
                if i.health == "normal"
                    disks.push i
            @vm.disk_num = disks.length
        $(@sd.raids).on "updated", (e, source) =>
            @vm.raid_num = source.items.length
        $(@sd.volumes).on "updated", (e, source) =>
            @vm.volume_num = source.items.length
        $(@sd.initrs).on "updated", (e, source) =>
            @vm.initr_num = source.items.length

        $(@sd.stats).on "updated", (e, source) =>
            if @has_rendered
                latest = source.items[source.items.length-1]
                @vm.cpu_load  = parseInt latest.cpu
                @vm.mem_load  = parseInt latest.mem
                @vm.temp_load = parseInt latest.temp
                @refresh_flow()

        $(@sd.journals).on "updated", (e, source) =>
            @vm.journals = @add_time_to_journal source.items[..]

    define_vm: (vm) =>
        vm.lang = lang.overviewpage
        vm.disk_num = 0
        vm.raid_num = 0
        vm.volume_num = 0
        vm.initr_num = 0
        vm.cpu_load = 0
        vm.mem_load = 0
        vm.temp_load = 0
        vm.journals = []
        vm.flow_type = "fwrite_mb"
        vm.rendered = @rendered

        vm.switch_flow_type = (e) =>
            v = $(e.target).data("flow-type")                 #make sure to show fread_mb or fwrite_mb
            vm.flow_type = v
            @flow_max = 0
        vm.switch_to_page = @switch_to_page
        
        vm.$watch "cpu_load", (nval, oval) =>
            $("#cpu-load").data("easyPieChart").update?(nval) if @has_rendered
            return
        vm.$watch "mem_load", (nval, oval) =>
            $("#mem-load").data("easyPieChart").update?(nval) if @has_rendered
            return
        vm.$watch "temp_load", (nval, oval) =>
            $("#temp-load").data("easyPieChart").update?(nval) if @has_rendered
            return
        
    rendered: () =>
        super()
        opt = animate: 1000, size: 128, lineWidth: 10, lineCap: "butt", barColor: ""
        opt.barColor = App.getLayoutColorCode "green"
        $("#cpu-load").easyPieChart opt
        $("#cpu-load").data("easyPieChart").update? @vm.cpu_load
        $("#mem-load").easyPieChart opt
        $("#mem-load").data("easyPieChart").update? @vm.mem_load
        $("#temp-load").easyPieChart opt
        $("#temp-load").data("easyPieChart").update? @vm.temp_load

        $scroller = $("#journals-scroller")
        $scroller.slimScroll
            size: '7px'
            color: '#a1b2bd'
            position: 'right'
            height: $scroller.attr("data-height")
            alwaysVisible: true
            railVisible: false
            disableFadeOut: true
            railDraggable: false

        [max, ticks] = @flow_data_opt()
        @plot_flow max, ticks

    flow_data_opt: () =>
        type = @flow_type()
        #type = @vm.flow_type
        #other_type = @combine_type()
        #flow_peak = Math.max(((sample[type] + sample[other_type]) for sample in @sd.stats.items)...)
        flow_peak = Math.max((sample[type] for sample in @sd.stats.items)...)
        if flow_peak < 10
            opts = ({peak: 3+3*i, max: 6+3*i, ticks:[0, 2+1*i, 4+2*i, 6+3*i]} for i in [0..4])
        else
            opts = ({peak: 30+30*i, max: 60+30*i, ticks:[0, 20+10*i, 40+20*i, 60+30*i]} for i in [0..40])
        for {peak, max, ticks} in opts
            if flow_peak < peak
                break
        return [max, ticks]

    flow_data: () =>
        type = @flow_type()
        # type = @vm.flow_type
        #other_type = @combine_type()
        offset = 120 - @sd.stats.items.length
        #data = ([i+offset, (sample[type] + sample[other_type])] for sample, i in @sd.stats.items)
        data = ([i+offset, sample[type]] for sample, i in @sd.stats.items)
        zero = [0...offset].map (e) -> [e, 0]
        zero.concat data

    flow_type: =>
        feature = @sd.systeminfo.data.feature
        rw = if @vm.flow_type is "fwrite_mb" then "write" else "read"
        if "monfs" in feature
            return "f#{rw}_mb"
        else if "xfs" in feature
            return "n#{rw}_mb"
        else
            return "#{rw}_mb"

    add_time_to_journal:(items) =>
            journals = []
            change_time = `function funConvertUTCToNormalDateTime(utc)
            {
                var date = new Date(utc);
                var ndt;
                ndt = date.getFullYear()+"/"+(date.getMonth()+1)+"/"+date.getDate()+"-"+date.getHours()+":"+date.getMinutes()+":"+date.getSeconds();
                return ndt;
            }`
            for item in items
                localtime = change_time(item.created_at*1000)
                item.message =  "[#{localtime}]  #{item.message}"
                journals.push item
            return journals
            
    combine_type: ->
        if @vm.flow_type[0] is "f"
            type = @vm.flow_type.slice 1
        else
            type = "f" + @vm.flow_type
        type

    plot_flow: (max, ticks) =>
        @$flow_stats = $.plot $("#flow_stats"), [@flow_data()],
            series:
                shadowSize: 1
            lines:
                show: true
                lineWidth: 0.2
                fill: true
                fillColor:
                    colors: [
                        {opacity: 0.1}
                        {opacity: 1}
                    ]
            yaxis:
                min: 0
                max: max
                tickFormatter: (v) -> "#{v}MB"
                ticks: ticks
            xaxis:
                show: false
            colors: ["#6ef146"]
            grid:
                tickColor: "#a8a3a3"
                borderWidth: 0

    refresh_flow: () =>
        [max, ticks] = @flow_data_opt()
        if max is @flow_max
            @$flow_stats.setData [@flow_data()]
            @$flow_stats.draw()
        else
            @flow_max = max
            @plot_flow(max, ticks)

class DiskPage extends Page
    constructor: (@sd) ->
        super "diskpage-", "html/diskpage.html"
        $(@sd.disks).on "updated", (e, source) =>
            @vm.disks = @subitems()
            @vm.need_format = @need_format()
            @vm.slots = @get_slots()
            @vm.raids = @get_raids()

    define_vm: (vm) =>
        vm.disks = @subitems()
        vm.slots = @get_slots()
        vm.raids = @get_raids()
        vm.lang = lang.diskpage
        vm.fattr_health = fattr.health
        vm.fattr_role = fattr.role
        vm.fattr_host = fattr.host
        vm.fattr_cap = fattr.cap
        vm.fattr_import = fattr._import
        vm.fattr_disk_status = fattr.disk_status
        vm.fattr_raid_status = fattr.raid_status
        vm.format_disk = @format_disk
        vm.format_all = @format_all
        vm.need_format = @need_format()
        
        vm.disk_list = @disk_list
        
    rendered: () =>
        super()
        $("[data-toggle='tooltip']").tooltip()
        $ ->
        $("#myTab li:eq(0) a").tab "show"

    subitems: () =>
        subitems @sd.disks.items,location:"",host:"",health:"",raid:"",role:"",cap_sector:""

    get_slots: () =>
        slotgroups = []
        slotgroup = []

        dsu_disk_num = 0
        raid_color_map = @_get_raid_color_map()
        for dsu in @sd.dsus.items
            for i in [1..dsu.support_disk_nr]
                o = @_has_disk(i, dsu, dsu_disk_num)
                o.raidcolor = raid_color_map[o.raid]
                o.info = @_get_disk_info(i, dsu)
                slotgroup.push o
                if i%4 is 0
                    slotgroups.push slotgroup
                    slotgroup = []
            dsu_disk_num = dsu_disk_num + dsu.support_disk_nr

        console.log slotgroups
        return slotgroups

    get_raids: () =>
        raids = []
        raid_color_map = @_get_raid_color_map()
        for key, value of raid_color_map
            o = name:key, color:value
            raids.push o
        return raids

    disk_list: (disks) =>
        if disks.info == "none"
            return "空盘"
        else
            return @_translate(disks.info)
        
    _translate: (obj) =>
        status = ''
        health = {'normal':'正常', 'down':'下线', 'failed':'损坏'}
        role = {'data':'数据盘', 'spare':'热备盘', 'unused':'未使用', \
        'kicked':'损坏', 'global_spare':'全局热备盘', 'data&spare':'数据热备盘'}
        type = {'enterprise': '企业盘', 'monitor': '监控盘', 'sas': 'SAS盘'}
        
        $.each obj, (key, val) ->
            switch key
                when 'cap_sector'
                    status += '容量: ' + fattr.cap(val)+ '<br/>'
                when 'health'
                    status += '健康: ' + health[val] + '<br/>'
                when 'role'
                    status += '状态: ' + role[val] + '<br/>'
                when 'raid'
                    if val.length == 0
                        val = '无'
                    status += '阵列: ' + val + '<br/>'
                when 'vendor'
                    status += '品牌: ' + val + '<br/>'
                when 'sn'
                    status += '序列号: ' + val + '<br/>'
                when 'model'
                    status += '型号: ' + val + '<br/>'
                when 'type'
                    name = '未知'
                    mod = obj.model.match(/(\S*)-/)[1];
                    $.each disks_type, (j, k) ->
                        if mod in k
                            name = type[j]
                    status += '类型: ' + name + '<br/>'
                    
        status
        
    _get_disk_info: (slotNo, dsu) =>
        for disk in @sd.disks.items
            if disk.location is "#{dsu.location}.#{slotNo}"
                info = health:disk.health, cap_sector:disk.cap_sector, \
                role:disk.role, raid:disk.raid, vendor:disk.vendor, \
                sn:disk.sn, model:disk.model, type:disk.type
                return info
        'none'
        
    _has_disk: (slotNo, dsu, dsu_disk_num) =>
        loc = "#{dsu_disk_num + slotNo}"
        for disk in @subitems()
            if disk.location is "#{dsu.location}.#{slotNo}"
                rdname = if disk.raid is ""\
                    then "noraid"\
                    else disk.raid
                rdrole = if disk.health is "down"\
                    then "down"\
                    else disk.role
                o = slot: loc, role:rdrole, raid:rdname, raidcolor: ""
                return o
        o = slot: loc, role:"nodisk", raid:"noraid", raidcolor: ""
        return o

    _get_raid_color_map: () =>
        map = {}
        raids = []
        i = 1
        has_global_spare = false
        for disk in @subitems()
            if disk.role is "global_spare"
                has_global_spare = true
                continue
            rdname = if disk.raid is ""\
                then "noraid"\
                else disk.raid
            if rdname not in raids
                raids.push rdname
        for raid in raids
            map[raid] = "color#{i}"
            i = i + 1
        map["noraid"] = "color0"
        if has_global_spare is true
            map["global_spare"] = "color5"
        return map

    format_disk: (element) =>
        if element.host is "native"
            return
        (new ConfirmModal lang.diskpage.format_warning(element.location), =>
            @frozen()
            chain = new Chain
            chain.chain =>
                (new DiskRest @sd.host).format element.location
            chain.chain @sd.update("disks")
            show_chain_progress(chain).done =>
                @attach()
        ).attach()

    format_all: =>
        disks = @_need_format_disks()
        (new ConfirmModal lang.diskpage.format_all_warning, =>
            @frozen()
            chain = new Chain
            rest = new DiskRest @sd.host
            i = 0
            for disk in disks
                chain.chain ->
                    (rest.format disks[i].location).done -> i += 1
            chain.chain @sd.update("disks")
            show_chain_progress(chain).done =>
                @attach()
        ).attach()

    need_format: =>
        return if (@_need_format_disks()).length isnt 0 then true else false

    _need_format_disks: =>
        disks = @subitems()
        needs = (disk for disk in disks when disk.host isnt "native")

class RaidPage extends DetailTablePage
    constructor: (@sd) ->
        super "raidpage-", "html/raidpage.html"

        table_update_listener @sd.raids, "#raid-table", =>
            @vm.raids = @subitems() if not @has_frozen

        $(@sd).on "raid", (e, raid) =>
            for r in @sd.raids.items
                if r.id is raid.id
                    r.health = raid.health
                    r.rqr_count = raid.rqr_count
                    r.rebuilding = raid.rebuilding
                    r.rebuild_progress = raid.rebuild_progress
            for r in @vm.raids
                if r.id is raid.id
                    r.rqr_count = raid.rqr_count
                    if r.rebuilding and raid.health == 'normal'
                        count = 5
                        delta = (1-r.rebuild_progress) / count
                        i = 0
                        tid = setInterval (=>
                            if i < 5
                                r.rebuild_progress += delta
                                i+=1
                            else
                                clearInterval tid
                                r.health = raid.health
                                r.rebuilding = raid.rebuilding
                                r.rebuild_progress = raid.rebuild_progress), 800
                    else
                        r.health = raid.health
                        r.rebuilding = raid.rebuilding
                        r.rebuild_progress = raid.rebuild_progress

    define_vm: (vm) =>
        vm.raids = @subitems()
        vm.lang = lang.raidpage
        vm.fattr_health = fattr.health
        vm.fattr_rebuilding = fattr.rebuilding
        vm.fattr_cap_usage = fattr.cap_usage_raid
        vm.all_checked = false

        vm.detail = @detail
        vm.create_raid = @create_raid
        vm.delete_raid = @delete_raid
        vm.set_disk_role = @set_disk_role

        vm.$watch "all_checked", =>
            for r in vm.raids
                r.checked = vm.all_checked

    subitems: () =>
        subitems(@sd.raids.items, id:"", name:"", level:"", chunk_kb:"",\
            health:"", rqr_count:"", rebuilding:"", rebuild_progress:0,\
            cap_sector:"", used_cap_sector:"", detail_closed:true, checked:false)

    rendered: () =>
        @vm.raids = @subitems() if not @has_frozen
        super()

        @data_table = $("#raid-table").dataTable(
            sDom: 't'
            oLanguage:
                sEmptyTable: "没有数据")

    detail_html: (raid) =>
        html = avalon_templ raid.id, "html/raid_detail_row.html"
        o = @sd.raids.get raid.id
        vm = avalon.define raid.id, (vm) =>
            vm.disks = subitems @sd.raid_disks(o),location:"",health:"",role:""
            vm.lang  = lang.raidpage.detail_row
            vm.fattr_health = fattr.health
            vm.fattr_role   = fattr.role

        $(@sd.disks).on "updated.#{raid.id}", (e, source) =>
            vm.disks = subitems @sd.raid_disks(o),location:"",health:"",role:""
        return [html, vm]

    close_detial: (raid) =>
        $(@sd.disks).off ".#{raid.id}"

    set_disk_role: () =>
        if @sd.raids.items.length > 0
            (new RaidSetDiskRoleModal(@sd, this)).attach()
        else
            (new MessageModal(lang.raid_warning.no_raid)).attach()

    create_raid: () =>
        (new RaidCreateModal(@sd, this)).attach()

    delete_raid: () =>
        deleted = ($.extend({},r.$model) for r in @vm.raids when r.checked)
        if deleted.length isnt 0
            (new RaidDeleteModal(@sd, this, deleted)).attach()
        else
            (new MessageModal(lang.raid_warning.no_deleted_raid)).attach()

class VolumePage extends DetailTablePage
    constructor: (@sd) ->
        super "volumepage-", "html/volumepage.html"
        table_update_listener @sd.volumes, '#volume-table', =>
            @vm.volumes = @subitems() if not @has_frozen
        table_update_listener @sd.filesystem, '#volume-table', =>
            @vm.volumes = @subitems() if not @has_frozen
        $(@sd.systeminfo).on "updated", (e, source) =>
            feature = @sd.systeminfo.data.feature
            @vm.show_fs = if "monfs" in feature or "xfs" in feature then true else false
            @fs_type = if "monfs" in feature then "monfs" else if "xfs" in feature then "xfs"
            @vm.show_cap = if "xfs" in feature then true else false
            @vm.show_cap_new = if "monfs" in feature or "ipsan" in feature then true else false
            @vm.show_precreate = if "monfs" in feature or "xfs" in feature and @_settings.znv then true else false
       
        @show_chosendir = @_settings.chosendir      #cangyu varsion can choose the target directory to mount
         
        failed_volumes = []
        @lock = false
        $(@sd).on "volume", (e, volume) =>
            @lock = volume.syncing
            if @_settings.sync
                if volume.event == "volume.created"
                    @lock = true
                else if volume.event == "volume.sync_done"
                    @lock = false                    
            for r in @sd.volumes.items
                if r.id is volume.id
                    r.sync_progress = volume.sync_progress
                    r.sync = volume.syncing
                    r.event = volume.event
            for r in @vm.volumes
                if r.id is volume.id
                    r.sync_progress = volume.sync_progress
                    r.syncing = volume.syncing
                    r.event = volume.event                               
            
            real_failed_volumes = []
            if volume.event == "volume.failed"
                volume = @sd.volumes.get e.uuid
                failed_volumes.push r
            for i in @sd.volumes.items
                if i.health == "failed"
                    real_failed_volumes.push i
            if failed_volumes.length == real_failed_volumes.length and failed_volumes.length
                (new SyncDeleteModal(@sd, this, real_failed_volumes)).attach()
                failed_volumes = []
                return

    define_vm: (vm) =>
        @_settings = new (require("settings").Settings)
        vm.volumes = @subitems()
        vm.lang = lang.volumepage
        vm.fattr_health = fattr.health
        vm.fattr_cap = fattr.cap
        vm.fattr_precreating = fattr.precreating        
        vm.detail = @detail
        vm.all_checked = false
        vm.create_volume = @create_volume
        vm.delete_volume = @delete_volume
        vm.enable_fs  = @enable_fs
        vm.disable_fs = @disable_fs
        vm.fattr_synchronizing = fattr.synchronizing
        vm.fattr_cap_usage_vol = fattr.cap_usage_vol
        
        vm.show_sync = @_settings.sync
        vm.enable_sync = @enable_sync
        vm.pause_synv = @pause_sync
        vm.disable_sync = @disable_sync      
        vm.sync_switch = @sync_switch
        
        vm.show_fs = @show_fs
        
        
        vm.show_precreate = @show_precreate
        vm.pre_create = @pre_create
        vm.server_start = @server_start
        vm.server_stop = @server_stop
        
        vm.show_cap = @show_cap
        vm.$watch "all_checked", =>
            for v in vm.volumes
                v.checked = vm.all_checked



    subitems: () =>
        items = subitems @sd.volumes.items, id:"", name:"", health:"", cap_sector:"",\
             used:"", detail_closed:true, checked:false, fs_action:"enable", syncing:'', sync_progress: 0,\
             precreating:"", precreate_progress: "", precreate_action:"unavail",\
             event: ""     
        for v in items
            if v.used
                v.fs_action = "disable"
                v.precreate_action = "precreating"
                if v.precreating isnt true and v.precreate_progress == 0
                    v.precreate_action = "enable_precreate"                   
            else
                v.fs_action = "enable"
                v.precreate_action = "unavail"                        
        return items  
        
    rendered: () =>
        super()
        @vm.volumes = @subitems() if not @has_frozen
        @data_table = $("#volume-table").dataTable dtable_opt(retrieve: true)
        $(".dataTables_filter input").addClass "m-wrap small"
        $(".dataTables_length select").addClass "m-wrap small"
    
    detail_html: (volume) =>
        html = avalon_templ volume.id, "html/volume_detail_row.html"
        o = @sd.volumes.get volume.id
        vm = avalon.define volume.id, (vm) =>
            vm.initrs = subitems @sd.volume_initrs(o),active_session:"",wwn:""
            vm.lang = lang.volumepage.detail_row
            vm.fattr_active_session = fattr.active_session

        $(@sd.initrs).on "updated.#{volume.id}", (e, source) =>
            vm.initrs = subitems @sd.volume_initrs(o),active_session:"",wwn:""
        return [html, vm]

    close_detial: (volume) =>
        $(@sd.initrs).off ".#{volume.id}"

    create_volume: () =>
        if @lock
            volume_syncing = []
            for i in @subitems()
                if i.syncing == true
                    volume_syncing.push i.name        
            (new MessageModal lang.volumepage.th_syncing_warning(volume_syncing)).attach()
            return
            
        raids_available = []
        for i in @sd.raids.items
            if i.health == "normal"
                raids_available.push i
        
        if raids_available.length > 0
            
            (new VolumeCreateModal(@sd, this)).attach()
        else
            (new MessageModal(lang.volume_warning.no_raid)).attach()

    delete_volume: () =>
        deleted = ($.extend({},v.$model) for v in @vm.volumes when v.checked)
        lvs_with_fs = []
        for fs_o in @sd.filesystem.data
            lvs_with_fs.push fs_o.volume

        for v in deleted
            if v.used
                if v.name in lvs_with_fs
                    (new MessageModal(lang.volume_warning.fs_on_volume(v.name))).attach()
                else if @sd.volume_initrs(v).length isnt 0
                    (new MessageModal(lang.volume_warning.volume_mapped_to_initrs(v.name))).attach()
                return
            else if @lock
                volume_syncing = []
                for i in @subitems()
                    if i.syncing == true
                        volume_syncing.push i.name             
                (new MessageModal lang.volumepage.th_syncing_warning(volume_syncing)).attach()
                return
        if deleted.length isnt 0
            (new VolumeDeleteModal(@sd, this, deleted)).attach()
        else
            (new MessageModal(lang.volume_warning.no_deleted_volume)).attach()

    _apply_fs_name: () =>
        max = @_settings.fs_max
        used_names=[]
        availiable_names=[]
        for fs_o in @sd.filesystem.data
            used_names.push fs_o.name
        for i in [1..max]
            if "myfs#{i}" in used_names
                continue
            else
                availiable_names.push "myfs#{i}"

        if availiable_names.length is 0
            return ""
        else
            return availiable_names[0]

    enable_fs: (v) =>
        if @sync
            (new MessageModal lang.volumepage.th_syncing_warning).attach()
            return
        fs_name = @_apply_fs_name()
        feature = @sd.systeminfo.data.feature[0]
        
        if v.used
            (new MessageModal(lang.volume_warning.volume_mapped_to_fs(v.name))).attach()
        else if fs_name is "" 
            if 'monfs' == feature 
                (new MessageModal(lang.volume_warning.only_support_one_fs)).attach()
            else if 'xfs' == feature
                (new MessageModal(lang.volume_warning.over_max_fs)).attach()
        else if @show_chosendir
            (new FsCreateModal(@sd, this, v.name)).attach()
        else if @_settings.znv
            (new FsChooseModal(@sd, this, fs_name, v.name)).attach()            
        else
            (new ConfirmModal(lang.volume_warning.enable_fs, =>
                @frozen()
                chain = new Chain()
                chain.chain(=> (new FileSystemRest(@sd.host)).create fs_name, @fs_type, v.name)
                    .chain @sd.update("filesystem")
                show_chain_progress(chain).done =>
                    @attach()
                .fail (data)=>
                    (new MessageModal(lang.volume_warning.over_max_fs)).attach()
                    @attach())).attach()
                    
    disable_fs: (v) =>
        if @sync
            (new MessageModal lang.volumepage.th_syncing_warning).attach()
            return

        fs_name = ""
        for fs_o in @sd.filesystem.data
            if fs_o.volume is v.name
                fs_name = fs_o.name
                break

        (new ConfirmModal(lang.volume_warning.disable_fs, =>
            @frozen()
            chain = new Chain()
            chain.chain(=> (new FileSystemRest(@sd.host)).delete fs_name)
                .chain @sd.update("filesystem")
            show_chain_progress(chain).done =>
                @attach())).attach()

    sync_switch: (v) =>
        console.log v
        if v.syncing
            @disable_sync(v)
        else
            @enable_sync(v)           

            
    enable_sync: (v) =>
        if v.health != 'normal'
            (new MessageModal lang.volume_warning.disable_sync).attach()
            return    
        (new ConfirmModal(lang.volume_warning.enable_sync(v.name), =>
            @frozen()
            chain = new Chain()
            chain.chain => 
                (new SyncConfigRest(@sd.host)).sync_enable(v.name)
            show_chain_progress(chain,true).done =>
                @attach()
            .fail (data) =>
                (new MessageModal lang.volume_warning.syncing_error).attach()
            )).attach()               
                #(new MessageModal lang.volumepage.syncing).attach())

    disable_sync: (v) =>
        chain = new Chain()
        chain.chain => 
            (new SyncConfigRest(@sd.host)).sync_disable(v.name)
        (show_chain_progress chain).done =>
            @attach()
        .fail (data) =>
            (new MessageModal lang.volume_warning.syncing_error).attach()
            
    pre_create: (v) =>
        chain = new Chain
        chain.chain(=> (new ZnvConfigRest(@sd.host)).precreate v.name)
         #   .chain @sd.update("volumes")
        (show_chain_progress chain).done 

    server_start: (bool) =>
        chain = new Chain
        chain.chain =>
            (new ZnvConfigRest(@sd.host)).start_service(bool)
        (show_chain_progress chain).done =>
            (new MessageModal lang.volumepage.btn_enable_server).attach()

    server_stop: (bool) =>
        chain = new Chain
        chain.chain =>
            (new ZnvConfigRest(@sd.host)).stop_service(bool)
        (show_chain_progress chain).done (data)=>
            console.log data
            (new MessageModal lang.volumepage.btn_disable_server).attach()
            
class InitrPage extends DetailTablePage
    constructor: (@sd) ->
        super "initrpage-", "html/initrpage.html"

        table_update_listener @sd.initrs, "#initr-table", =>
            @vm.initrs = @subitems() if not @has_frozen

        $(@sd).on "initr", (e, initr) =>
            for i in @vm.initrs
                if i.id is initr.id
                    i.active_session = initr.active_session

        @vm.show_iscsi = if @_iscsi.iScSiAvalable() and !@_settings.fc then true else false


    define_vm: (vm) =>
        @_settings = new (require("settings").Settings)
        @_iscsi = new IScSiManager
        vm.initrs = @subitems()
        vm.lang = lang.initrpage
        vm.fattr_active_session = fattr.active_session
        vm.fattr_show_link = fattr.show_link
        vm.detail = @detail
        vm.all_checked = false

        vm.create_initr = @create_initr
        vm.delete_initr = @delete_initr

        vm.map_volumes = @map_volumes
        vm.unmap_volumes = @unmap_volumes

        vm.show_iscsi = @show_iscsi
        vm.link_initr = @link_initr
        vm.unlink_initr = @unlink_initr
        
        vm.$watch "all_checked", =>
            for v in vm.initrs
                v.checked = vm.all_checked
    
    subitems: () =>
        arrays = subitems @sd.initrs.items, id:"", wwn:"", active_session:"",\
            portals:"", detail_closed:true, checked:false 
        for item in arrays
            item.name = item.wwn
            item.iface = (portal for portal in item.portals).join ", "
        return arrays

    rendered: () =>
        @vm.initrs = @subitems()
        @data_table = $("#initr-table").dataTable dtable_opt(retrieve: true)
        $(".dataTables_filter input").addClass "m-wrap small"
        $(".dataTables_length select").addClass "m-wrap small"
        super()



            
    detail_html: (initr) =>
        html = avalon_templ initr.id, "html/initr_detail_row.html"
        o = @sd.initrs.get initr.id
        vm = avalon.define initr.id, (vm) =>
            vm.volumes = subitems @sd.initr_volumes(o),name:""
            vm.lang = lang.initrpage.detail_row
        return [html, vm]

    create_initr: () =>   
        (new InitrCreateModal @sd, this).attach()

    delete_initr: () =>
        selected = ($.extend({},i.$model) for i in @vm.initrs when i.checked)
        initrs = (@sd.initrs.get initr.id for initr in selected)
        if initrs.length == 0
            (new MessageModal lang.initr_warning.no_deleted_intir).attach()
        else
            for initr in initrs
                volumes = @sd.initr_volumes initr
                if volumes.length isnt 0
                    (new MessageModal lang.initr_warning.intitr_has_map(initr.wwn)).attach()
                    return
            (new InitrDeleteModal @sd, this, selected).attach()

    map_volumes: (index) =>
        selected = @sd.initrs.get @vm.initrs[index].id
        volumes = []
        for i in @sd.volumes.items
            if i.health == "normal"
                volumes.push i
        if volumes.length == 0
            (new MessageModal lang.initr_warning.no_spared_volume).attach()
        else if selected.active_session
            (new MessageModal lang.initr_warning.detect_iscsi(selected.wwn)).attach()
        else
            (new VolumeMapModal @sd, this, selected).attach()

    unmap_volumes: (index) =>
        selected = @sd.initrs.get @vm.initrs[index].id
        volumes = @sd.initr_volumes selected
        if volumes.length == 0
            (new MessageModal lang.initr_warning.no_attached_volume).attach()
        else if selected.active_session
            (new MessageModal lang.initr_warning.unmap_iscsi(selected.wwn)).attach()
        else
            (new VolumeUnmapModal @sd, this, selected).attach()

    link_initr: (index) =>
        for indexs in [0..@vm.initrs.length-1] when @sd.initrs.items[indexs].active_session is true
            (new MessageModal lang.initr_warning.intitr_has_link).attach()
            return
        selected = @sd.initrs.get @vm.initrs[index].id
        portals = []
        for portal in @sd.networks.items when portal.id in selected.portals
            portals.push portal.ipaddr
            @_iscsi.linkinit selected.wwn,portal.ipaddr
        (new ConfirmModal_link(
                lang.initr_link_warning.confirm_link(selected.wwn), =>
                    chain = new Chain()
                    @_iscsi_link index
            )).attach()

    unlink_initr: (index) =>
        selected = @sd.initrs.get @vm.initrs[index].id
        portals = []
        for portal in @sd.networks.items when portal.id in selected.portals
            portals.push portal.ipaddr
            @_iscsi.linkinit selected.wwn,portal.ipaddr
        (new ConfirmModal_unlink(
                lang.initr_link_warning.undo_link(selected.wwn), =>
                    chain = new Chain()
                    @_iscsi_unlink index
            )).attach()

    _iscsi_link: (index) =>
        selected = @sd.initrs.get @vm.initrs[index].id
        portals = []
        for portal in @sd.networks.items when portal.id in selected.portals
            portals.push portal.ipaddr 
        @frozen()
        chain = new Chain()
        chain.chain @sd.update('initrs')
        show_chain_progress(chain).done =>
            if @_iscsi.connect selected.wwn, portals
                @attach()
            else
                (new MessageModal(lang.initr_link_warning.link_err)).attach()
                @attach()
        .fail =>
            @attach()
        chains = new Chain()
        chains.chain @sd.update('initrs')

    _iscsi_unlink: (index) =>
        selected = @sd.initrs.get @vm.initrs[index].id
        portals = []
        for portal in @sd.networks.items when portal.id in selected.portals
            portals.push portal.ipaddr 
        @frozen()
        chain = new Chain()
        chain.chain @sd.update('initrs')
        show_chain_progress(chain).done =>
            if @_iscsi.disconnect selected.wwn, portals
                @attach()
            else
                (new MessageModal(lang.initr_link_warning.link_err)).attach()
                @attach()
        .fail =>
            @attach()
        chains = new Chain()
        chains.chain @sd.update('initrs')
        
            
class SettingPage extends Page
    constructor: (@dview, @sd) ->
        super "settingpage-", "html/settingpage.html"
        @edited = null
        @settings = new SettingsManager
        $(@sd.networks).on "updated", (e, source) =>
            @vm.ifaces = @subitems()
            @vm.able_bonding = @_able_bonding()
            @vm.local_serverip = @sd.networks.items[1].ipaddr
            
        $(@sd.gateway).on "updated", (e, source) =>
            @vm.gateway = @sd.gateway.data.gateway

        @vm.server_options = [
          { value: "store_server", msg: "存储服务器" }
          { value: "forward_server", msg: "转发服务器" }
        ]
        
    #znv_server
               
    define_vm: (vm) =>
        @_settings = new (require("settings").Settings) 
        vm.lang = lang.settingpage
        vm.ifaces = @subitems()
        vm.gateway = @sd.gateway.data.gateway
        vm.old_passwd = ""
        vm.new_passwd = ""
        vm.confirm_passwd = ""
        vm.submit_passwd = @submit_passwd
        vm.keypress_passwd = @keypress_passwd
        vm.edit_iface = (e) =>
            for i in @vm.ifaces
                i.edit = false
            e.edit = true
            @edited = e
        vm.cancel_edit_iface = (e) =>
            e.edit = false
            @edited = null
            i = @sd.networks.get e.id
            e.ipaddr  = i.ipaddr
            e.netmask = i.netmask
        vm.submit_iface   = @submit_iface
        vm.submit_gateway = @submit_gateway
        vm.able_bonding = true
        vm.eth_bonding = @eth_bonding
        vm.eth_bonding_cancel = @eth_bonding_cancel
        
        vm.znv_server = @znv_server
        vm.server_options = ""
        vm.enable_server = true
        vm.server_switch = @_settings.znv
        vm.select_ct = true
        vm.serverid = ""
        vm.local_serverip = ""
        vm.local_serverport = "8003"
        vm.cmssverip = ""
        vm.cmssverport = "8000"
        vm.directory ="/nvr/d1;/nvr/d2"
                
    subitems: () =>
        items = subitems @sd.networks.items,id:"",ipaddr:"",iface:"",netmask:"",type:"",edit:false
        removable = []
        if not @_able_bonding()
            for eth in items
                removable.push eth if eth.type isnt "bond-slave"
            return removable
        items

    rendered: () =>
        super()
        $('.tooltips').tooltip()
        $.validator.addMethod("same", (val, element) =>
            if @vm.new_passwd != @vm.confirm_passwd
                return false
            else
                return true
        , "两次输入的新密码不一致")

        $("#server_select").chosen()
        chosen = $("#server_select")
        chosen.change =>
            if chosen.val() == "store_server"
                @vm.local_serverport = 8003
                @vm.select_ct = true
            else
                @vm.local_serverport = 8002
                @vm.select_ct = false
                
        $("form.passwd").validate(
            valid_opt(
                rules:
                    old_passwd:
                        required: true
                        maxlength: 32
                    new_passwd:
                        required: true
                        maxlength: 32
                    confirm_passwd:
                        required: true
                        maxlength: 32
                        same: true
                messages:
                    old_passwd:
                        required: "请输入您的旧密码"
                        maxlength: "密码长度不能超过32个字符"
                    new_passwd:
                        required: "请输入您的新密码"
                        maxlength: "密码长度不能超过32个字符"
                    confirm_passwd:
                        required: "请再次输入您的新密码"
                        maxlength: "密码长度不能超过32个字符"))

        Netmask = require("netmask").Netmask
        $.validator.addMethod("validIP", (val, element) =>
            regex = /^\d{1,3}(\.\d{1,3}){3}$/
            if not regex.test val
                return false
            try
                n = new Netmask(val)
                return true
            catch error
                return false
        )

        $.validator.addMethod("validport", (val, element) =>
            regex = /^[0-9]*$/
            if not regex.test val
                return false
            try
                n = new Netmask(val)
                return true 
            catch error
                return true                
        )
                
        $.validator.addMethod("samesubnet", (val, element) =>
            try
                subnet = new Netmask("#{@edited.ipaddr}/#{@edited.netmask}")
                for n in @sd.networks.items
                    if n.iface == @edited.iface
                        continue
                    if n.ipaddr isnt "" and subnet.contains n.ipaddr
                        return false
                return true
            catch error
                return false
        ,(params, element) =>
            try
                subnet = new Netmask("#{@edited.ipaddr}/#{@edited.netmask}")
                for n in @sd.networks.items
                    if n.iface == @edited.iface
                        continue
                    if n.ipaddr isnt "" and subnet.contains n.ipaddr
                        return "和#{n.iface}处在同一网段，请重新配置网卡"
            catch error
                return "网卡配置错误，请重新配置网卡"
        )
        
        $.validator.addMethod("using", (val, element) =>
            for initr in @sd.initrs.items
                if @edited.iface in initr.portals
                    return false
            return true
        ,(val, element) =>
            for initr in @sd.initrs.items
                if @edited.iface in initr.portals
                    return "客户端#{initr.wwn}正在使用#{@edited.iface}，请删除客户端，再配置网卡"
        )

        $("#network-table").validate(
            valid_opt(
                rules:
                    ipaddr:
                        required: true
                        validIP: true
                        samesubnet: true
                        using: true
                    netmask:
                        required: true
                        validIP: true
                messages:
                    ipaddr:
                        required: "请输入IP地址"
                        validIP: "无效IP地址"
                    netmask:
                        required: "请输入子网掩码"
                        validIP: "无效子网掩码"))

        $.validator.addMethod("reachable", (val, element) =>
            for n in @sd.networks.items
                try
                    subnet = new Netmask("#{n.ipaddr}/#{n.netmask}")
                catch error
                    # some ifaces have empty ipaddr, so ignore it
                    continue

                if subnet.contains val
                    return true
            return false
        )

        $("form.gateway").validate(
            valid_opt(
                rules:
                    gateway:
                        required: true
                        validIP: true
                        reachable: true
                messages:
                    gateway:
                        required: "请输入网关地址"
                        validIP: "无效网关地址"
                        reachable: "路由不在网卡网段内"))

        $("#server-table").validate(
            valid_opt(
                rules:
                    cmssverip:
                        required: true
                        validIP: true
                        reachable: true
                    cmssverport:
                        required: true
                        validport: true
                        #reachable: true
                messages:
                    cmssverip:
                        required: "请输入中心IP"
                        validIP: "无效IP地址"
                        reachable: "路由不在网卡网段内"
                    cmssverport:
                        required: "请输入监听端口"
                        validport: "无效端口"
                        #reachable: "端口不存在"
                        ))

        $("form.server").validate(
            valid_opt(
                rules:
                    serverid:
                        required: true
                        validport: true
                        #reachable: true
                    local_serverip:
                        required: true
                        validIP: true
                        reachable: true
                    local_serverport:
                        required: true
                        validport: true
                        #reachable: true
           
                messages:
                    serverid:
                        required: "请输入服务器ID"
                        validport: "无效服务器ID"
                        #reachable: "路由不在网卡网段内"                    
                    local_serverip:
                        required: "请输入本机IP"
                        validIP: "无效IP地址"
                        reachable: "路由不在网卡网段内"
                    local_serverport:
                        required: "请输入监听端口"
                        validport: "无效端口"
                        #reachable: "端口不存在"
                        ))

    submit_passwd: () =>
        if $("form.passwd").validate().form()
            if @vm.old_passwd is @vm.new_passwd
                (new MessageModal lang.settingpage.useradmin_error).attach()
            else
                chain = new Chain
                chain.chain =>
                    (new UserRest(@sd.host)).change_password("admin", @vm.old_passwd, @vm.new_passwd)

                (show_chain_progress chain).done =>
                    @vm.old_passwd = ""
                    @vm.new_passwd = ""
                    @vm.confirm_passwd = ""
                    (new MessageModal lang.settingpage.message_newpasswd_success).attach()


    keypress_passwd: (e) =>
        @submit_passwd() if e.which is 13

    submit_iface: (e) =>
        for portal in @sd.networks.items when portal.ipaddr is e.ipaddr
            (new MessageModal lang.settingpage.iface_error).attach()
            return
        if $("#network-table").validate().form()
            (new ConfirmModal(lang.network_warning.config_iface, =>
                e.edit = false
                @dview.reconnect = true
                chain = new Chain
                chain.chain =>
                    rest = new NetworkRest @sd.host
                    if e.type is "normal"
                        return rest.config e.iface,e.ipaddr,e.netmask
                    else if e.type is "bond-master"
                        return rest.modify_eth_bonding e.ipaddr, e.netmask
                show_chain_progress(chain, true).fail =>
                    index = window.adminview.find_nav_index @dview.menuid
                    window.adminview.remove_tab index if index isnt -1
            )).attach()

    submit_gateway: (e) =>
        if $("form.gateway").validate().form()
            (new ConfirmModal(lang.network_warning.config_gateway, =>
                chain = new Chain()
                chain.chain(=> (new GatewayRest(@sd.host)).config @vm.gateway)
                    .chain @sd.update("networks")
                show_chain_progress(chain).fail =>
                    @vm.gateway = @sd.gateway.ipaddr)).attach()

    znv_server: () =>
        if $("form.server").validate().form() and $("#server-table").validate().form()
            chain = new Chain
            chain.chain =>
                (new ZnvConfigRest(@sd.host)).znvconfig(@vm.select_ct, @vm.serverid, @vm.local_serverip, @vm.local_serverport, @vm.cmssverip, @vm.cmssverport, @vm.directory)
            (show_chain_progress chain).done =>
                (new MessageModal lang.settingpage.service_success).attach()

    _able_bonding: =>
        for eth in @sd.networks.items
            return false if (eth.type.indexOf "bond") isnt -1
        true

    eth_bonding: =>
        if @_has_initr()
            (new MessageModal lang.settingpage.btn_eth_bonding_warning).attach()
            return
        else
            (new EthBondingModal @sd, this).attach()

    eth_bonding_cancel: =>
        if @_has_initr()
            (new MessageModal lang.settingpage.btn_eth_bonding_warning).attach()
            return
        else
            (new ConfirmModal lang.eth_bonding_cancel_warning, =>
                @frozen()
                @dview.reconnect = true
                chain = new Chain
                chain.chain =>
                    (new NetworkRest @sd.host).cancel_eth_bonding()
                show_chain_progress(chain, true).fail =>
                    index = window.adminview.find_nav_index @dview.menuid
                    window.adminview.remove_tab index if index isnt -1
            ).attach()
            return

    _has_initr: =>
        @sd.initrs.items.length isnt 0

class QuickModePage extends Page
    constructor: (@dview, @sd) ->
        super "quickmodepage-", "html/quickmodepage.html"
        @create_files = true
        $(@sd.systeminfo).on "updated", (e, source) =>
            feature = @sd.systeminfo.data.feature
            @vm.show_fs = if "monfs" in feature or "xfs" in feature then true else false

    define_vm: (vm) =>
        vm.lang = lang.quickmodepage
        vm.enable_fs = false
        vm.raid_name = ""
        vm.volume_name = ""
        vm.initr_wwn = ""
        #vm.chunk = "32KB"
        vm.submit = @submit

        @_iscsi = new IScSiManager
        vm.show_iscsi = @_iscsi.iScSiAvalable()
        @enable_iscsi = @_iscsi.iScSiAvalable()

        vm.$watch "volume_name", =>
            vm.initr_wwn = "#{prefix_wwn}:#{vm.volume_name}"

    count_dsu_disks: (dsu) =>
        return (disk for disk in @sd.disks.items\
                         when disk.role is 'unused'\
                         and disk.location.indexOf(dsu.location) is 0).length

    prefer_dsu_location: () =>
        for dsu in @sd.dsus.items
            if @count_dsu_disks(dsu) >= 3
                return dsu.location
        return if @sd.dsus.length then @sd.dsus.items[0].location else '_'

    rendered: () =>
        super()
        #$("[data-toggle='popover']").popover()
        $(".tooltips").tooltip()      
        [rd, lv, wwn] = @_get_unique_names()
        @vm.raid_name   = rd
        @vm.volume_name = lv
        @vm.initr_wwn   = wwn
        $("input:radio").uniform()
        $(".basic-toggle-button").toggleButtons()
        @dsuui = new RaidCreateDSUUI(@sd, "#dsuui")
        @dsuui.attach()
        @add_child @dsuui

        $("#enable-fs").change =>
            @vm.enable_fs = $("#enable-fs").prop "checked"
            if @vm.enable_fs
                @enable_iscsi = false
            else
                @enable_iscsi = $("#enable-iscsi").prop "checked"
        $("#create-files").change =>
            @create_files = $("#create-files").prop "checked"
        $("#enable-iscsi").change =>
            @enable_iscsi = $("#enable-iscsi").prop "checked"

        dsu = @prefer_dsu_location()
        [raids..., spares] = (disk for disk in @sd.disks.items\
                                when disk.role is 'unused'\
                                and disk.location.indexOf(dsu) is 0)
        spares = [] if not spares?
        if raids.length < 3 and spares
            raids = raids.concat spares
            spares = []
        @dsuui.check_disks raids
        @dsuui.check_disks spares, "spare"
        @dsuui.active_tab dsu

        console.log @dsuui.getchunk()

        $.validator.addMethod("min-raid-disks", (val, element) =>
            return @dsuui.get_disks().length >= 3
        )

        $("form", @$dom).validate(
            valid_opt(
                rules:
                    "raid":
                        required: true
                        regex: "^[_a-zA-Z][-_a-zA-Z0-9]*$"
                        duplicated: @sd.raids.items
                        maxlength: 64
                    "volume":
                        required: true
                        regex: "^[_a-zA-Z][-_a-zA-Z0-9]*$"
                        duplicated: @sd.volumes.items
                        maxlength: 64
                    wwn:
                        required: true
                        regex: '^(iqn.2013-01.net.zbx.initiator:)(.*)$'
                        duplicated: @sd.initrs.items
                        maxlength: 96
                    "raid-disks-checkbox":
                        "min-raid-disks": true
                        maxlength: 24
                messages:
                    "raid":
                        required: "请输入阵列名称"
                        duplicated: "阵列名称已存在"
                        maxlength: "阵列名称长度不能超过64个字母"
                    "volume":
                        required: "请输入虚拟磁盘名称"
                        duplicated: "虚拟磁盘名称已存在"
                        maxlength: "虚拟磁盘名称长度不能超过64个字母"
                    wwn:
                        required: "请输入客户端名称"
                        duplicated: "客户端名称已存在"
                        maxlength: "客户端名称长度不能超过96个字母"
                    "raid-disks-checkbox":
                        "min-raid-disks": "级别5阵列最少需要3块磁盘"
                        maxlength: "阵列最多支持24个磁盘"))

    _has_name: (name, res, nattr="name") =>
        for i in res.items
            if name is i[nattr]
                return true
        return false
    
    _all_unique_names: (rd, lv, wwn) =>
        return not (@_has_name(rd, @sd.raids) or @_has_name(lv, @sd.volumes) or @_has_name(wwn, @sd.initrs, "wwn"))

    _get_unique_names: () =>
        rd_name = "rd"
        lv_name = "lv"
        wwn = "#{prefix_wwn}:#{lv_name}"
        if @_all_unique_names rd_name, lv_name, wwn
            return [rd_name, lv_name, wwn]
        else
            i = 1
            while true
                rd = "#{rd_name}-#{i}"
                lv = "#{lv_name}-#{i}"
                wwn = "#{prefix_wwn}:#{lv}"
                if @_all_unique_names rd, lv, wwn
                    return [rd, lv, wwn]
                i += 1

    _get_ifaces: =>
        removable = []
        if not @_able_bonding()
            for eth in @sd.networks.items
                removable.push eth if eth.type isnt "bond-slave"
            return removable
        @sd.networks.items

    _able_bonding: =>
        for eth in @sd.networks.items
            return false if (eth.type.indexOf "bond") isnt -1
        true

    submit: () =>
        if @dsuui.get_disks().length == 0
            (new MessageModal lang.quickmodepage.create_error).attach()
        else if @dsuui.get_disks().length <3
            (new MessageModal lang.quickmodepage.create_error_least).attach()
        else
            if $("form").validate().form()
                @create(@vm.raid_name, @dsuui.getchunk(), @dsuui.get_disks(), @dsuui.get_disks("spare"),\
                    @vm.volume_name, @vm.initr_wwn, @vm.enable_fs, @enable_iscsi, @create_files)

    create: (raid, chunk, raid_disks, spare_disks, volume, initr, enable_fs, enable_iscsi, create_files) =>
        raid_disks = raid_disks.join ","
        spare_disks = spare_disks.join ","

        for n in @_get_ifaces()
            if n.link and n.ipaddr isnt ""
                portals = n.iface
                break
        chain = new Chain
        chain.chain(=> (new RaidRest(@sd.host)).create(name: raid, level: 5,\
            chunk: chunk, raid_disks: raid_disks, spare_disks:spare_disks,\
            rebuild_priority:"", sync:"no", cache:""))
            .chain(=> (new VolumeRest(@sd.host)).create(name: volume,\
                raid: raid, capacity: "all"))
        if enable_fs
            chain.chain(=> (new FileSystemRest(@sd.host)).create "myfs", volume)
            ###
            if create_files
                chain.chain(=> (new CommandRest(@sd.host)).create_lw_files())
            ###
        else
            if not @sd.initrs.get initr
                chain.chain(=> (new InitiatorRest(@sd.host)).create(wwn:initr, portals:portals))
            chain.chain(=> (new InitiatorRest(@sd.host)).map initr, volume)
        chain.chain @sd.update("all")
        show_chain_progress(chain, false, false).done(=>
            if enable_iscsi
                ipaddr = (@sd.host.split ":")[0]
                @_iscsi_link initr, [ipaddr]
            if enable_fs and create_files
                setTimeout (new CommandRest(@sd.host)).create_lw_files, 1000
            @dview.switch_to_page "overview"
            @vm.enable_fs = false).fail(=>
            @vm.enable_fs = false)

    _iscsi_link: (initr, portals) ->
        try
            @_iscsi.connect initr, portals
        catch err
            console.log err

class MaintainPage extends Page
    constructor: (@dview, @sd) ->
        super "maintainpage-", "html/maintainpage.html"
        @settings = new SettingsManager
        $(@sd.systeminfo).on "updated", (e, source) =>
            @vm.server_version = "存储系统版本：#{@sd.systeminfo.data.version}"

    define_vm: (vm) =>
        _settings = new (require("settings").Settings)
        vm.lang = lang.maintainpage
        vm.diagnosis_url = "http://#{@sd.host}/api/diagnosis"
        vm.server_version = "存储系统版本：#{@sd.systeminfo.data.version}"
        vm.gui_version = "客户端版本：#{_settings.version}"
        vm.product_model = "产品型号：CYBX-4U24-T-DC"
        vm.poweroff = @poweroff
        vm.reboot = @reboot
        vm.sysinit = @sysinit
        vm.recover = @recover
        vm.scan_system = @scan_system
        vm.fs_scan = !_settings.sync
        vm.show_productmodel = _settings.product_model

    rendered: () =>
        super()
        $("#fileupload").fileupload(url:"http://#{@sd.host}/api/upgrade")
            .bind("fileuploaddone", (e, data) ->
                (new MessageModal(lang.maintainpage.message_upgrade_success)).attach())
        $("input[name=files]").click ->
            $("tbody.files").html ""

    poweroff: () =>
        (new ConfirmModal(lang.maintainpage.warning_poweroff, =>
            chain = new Chain()
            chain.chain => (new CommandRest(@dview.sd.host)).poweroff()
            show_chain_progress(chain, true).fail =>
                @settings.removeLoginedMachine @dview.host
                @sd.close_socket()
                arr_remove sds, @sd
                setTimeout(@dview.switch_to_login_page, 2000))).attach()

    reboot: () =>
        (new ConfirmModal(lang.maintainpage.warning_reboot, =>
            chain = new Chain()
            chain.chain => (new CommandRest(@dview.sd.host)).reboot()
            show_chain_progress(chain, true).fail =>
                @settings.removeLoginedMachine @dview.host
                @sd.close_socket()
                arr_remove sds, @sd
                setTimeout(@dview.switch_to_login_page, 2000)
                )).attach()

    sysinit: () =>
        (new ConfirmModal_more(@vm.lang.btn_sysinit,@vm.lang.warning_sysinit,@sd,@dview,@settings)).attach()

    recover: () =>
        bool = false
        for i in @sd.raids.items
            if i.health == "failed"
                bool = true
            else
                continue
        
        if bool
            (new ConfirmModal_more(@vm.lang.btn_recover,@vm.lang.warning_recover,@sd,@dview,@settings, this)).attach()
        else
            (new MessageModal(lang.maintainpage.warning_raids_safety)).attach()

    apply_fs_name: () =>
        fs_name = ""
        for fs_o in @sd.filesystem.data
            fs_name = fs_o.name
        return fs_name

    scan_system: (v) =>
        console.log @sd
        fs_name = @apply_fs_name(v)
        if @sd.filesystem.data.length == 0
            chain = new Chain()
            (show_chain_progress chain).done =>
                (new MessageModal lang.volume_warning.no_fs).attach()
        else
            (new ConfirmModal(lang.volume_warning.scan_fs, =>
                @frozen()
                fsrest = (new FileSystemRest(@sd.host))
               
                (fsrest.scan fs_name).done (data) =>
                    if data.status == "success" and data.detail.length > 0
                        (new ConfirmModal_scan(@sd, this, lang.volumepage.th_scan, lang.volumepage.th_scan_warning, data.detail)).attach()
                    else
                        (new MessageModal lang.volumepage.th_scan_safety).attach()
                    @attach()
                .fail =>
                    (new MessageModal lang.volume_warning.scan_fs_fail).attach()
                )).attach()
                
class LoginPage extends Page
    constructor: (@dview) ->
        super "loginpage-", "html/loginpage.html", class: "login"
        @try_login = false
        @_settings = new SettingsManager
        @settings = new (require("settings").Settings)

    define_vm: (vm) =>
        vm.lang = lang.login
        vm.device = ""
        vm.username = "admin"
        vm.passwd = ""
        #vm.passwd = "admin"
        vm.submit = @submit
        vm.keypress = @keypress
        vm.close_alert = @close_alert

    rendered: () =>
        super()
        
        $.validator.addMethod "isLogined", (value, element) ->
            not (new SettingsManager).isLoginedMachine value
        
        $(".login-form").validate(
            valid_opt(
                rules:
                    device:
                        required: true
                        isLogined: true
                    username:
                        required: true
                    passwd:
                        required: true
                messages:
                    device:
                        required: "请输入存储IP"
                        isLogined: "您已经登录该设备"
                    username:
                        required: "请输入用户名"
                    passwd:
                        required: "请输入密码"
                errorPlacement: (error, elem) ->
                    error.addClass("help-small no-left-padding").
                        insertAfter(elem.closest(".input-icon"))))

        $("#login-ip").typeahead(
            source: @_settings.getUsedMachines()
            items: 6
            updater: (item) =>
                @vm.device = item
        )

        @backstretch = $(".login").backstretch([
            "images/login-bg/1.jpg",
            "images/login-bg/2.jpg",
            "images/login-bg/3.jpg",
            "images/login-bg/4.jpg",
            ], fade: 1000, duration: 5000).data "backstretch"

        return

    attach: () =>
        super()
        return

    detach: () =>
        super()
        @backstretch?.pause?()

    change_device: (device) =>
        @vm.device = device

    close_alert: (e) =>
        $(".alert-error").hide()

    keypress: (e) =>
        @submit() if e.which is 13

    submit: () =>
        port = @settings.port
        return if @try_login
        if $(".login-form").validate().form()
            @try_login = true
            ifaces_request = new IfacesRest("#{@vm.device}:" + port).query()
            ifaces_request.done (data) =>
                if data.status is "success"
                    isLogined = false
                    login_machine = ""
                    settings = new SettingsManager
                    ifaces = (iface.split("/", 1)[0] for iface in data.detail)
                    for iface in ifaces
                        if settings.isLoginedMachine iface
                            isLogined = true
                            login_machine = iface
                    if isLogined
                        (new MessageModal(
                            lang.login.has_logged_error(login_machine))
                        ).attach()
                        @try_login = false
                    else
                        @_login()
                else
                    @_login()
            ifaces_request.fail =>
                @_login()
            
    _login: () =>
        port = @settings.port
        chain = new Chain
        chain.chain =>
            rest = new SessionRest("#{@vm.device}:" + port)
            query = rest.create @vm.username, @vm.passwd
            query.done (data) =>
                if data.status is "success"
                    @dview.token = data.detail.login_id
        chain.chain @dview.init @vm.device
        show_chain_progress(chain, true).done(=>
            version_request = new SystemInfoRest("#{@vm.device}:" + port).query()
            version_request.done (data) =>
                if data.status is "success"
                    _server_version = data.detail["gui version"].substring 0, 3
                    _app_version = @settings.version.substring 0, 3
                    @_init_device()
                    if _server_version == _app_version
                        @dview.attach()
                    else
                        (new MessageModal lang.login.version_invalid_error).attach()
                        @dview.attach()
            version_request.fail =>
                @_init_device()
                @dview.attach()
        ).fail(=>
            @try_login = false
            $('.alert-error', $('.login-form')).show())
            
        
    
    _init_device: =>
        @try_login = false
        @_settings.addUsedMachine @vm.device
        @_settings.addLoginedMachine @vm.device
        @_settings.addSearchedMachine @vm.device
        return

this.DetailTablePage = DetailTablePage
this.DiskPage = DiskPage
this.InitrPage = InitrPage
this.LoginPage = LoginPage
this.MaintainPage = MaintainPage
this.OverviewPage = OverviewPage
this.Page = Page
this.QuickModePage = QuickModePage
this.RaidPage = RaidPage
this.SettingPage = SettingPage
this.VolumePage = VolumePage