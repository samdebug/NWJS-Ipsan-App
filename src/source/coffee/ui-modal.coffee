class Modal extends AvalonTemplUI
    constructor: (@prefix, @src, @attr={}) ->
        $.extend(@attr, class: "modal fade")
        super @prefix, @src, "body", false, @attr

    attach: () =>
        $("body").modalmanager "loading"
        super()

    rendered: () =>
        super()
        $div = $("##{@id}")
        $div.on "hide", (e) =>
            if e.currentTarget == e.target
                setTimeout (=> @detach()), 1000
        $div.modal({backdrop:'static'})
        $(".tooltips").tooltip()

    hide: () =>
        $("##{@id}").modal("hide")

class MessageModal extends Modal
    constructor: (@message, @callback=null) ->
        super "message-", "html/message_modal.html"

    define_vm: (vm) =>
        vm.message = @message
        vm.lang = lang.message_modal
        vm.callback = => @callback?()

class MessageModal_reboot extends Modal
    constructor: (@message,@bottom,@dview,@sd,@settings) ->
        super "message-", "html/message_modal_reboot.html"
        
    define_vm: (vm) =>
        vm.message = @message
        vm.lang = lang.message_modal
        vm.recovered = @bottom
        vm.reboot = @reboot

    reboot: () =>
        chain = new Chain()
        chain.chain => (new CommandRest(@dview.sd.host)).reboot()
        @hide()
        show_chain_progress(chain, true).fail =>
            @settings.removeLoginedMachine @dview.host
            @sd.close_socket()
            arr_remove sds, @sd
            setTimeout(@dview.switch_to_login_page, 2000)

class ConfirmModal_unlink extends Modal
    constructor: (@message, @confirm, @cancel,@warn) ->
        super "confirm-", "html/confirm_Initr.html"

    define_vm: (vm) =>
        vm.message = @message
        vm.lang = lang.confirm_modal
        vm.warn = lang.initr_unlink_modal
        vm.submit_confirm = => @confirm?()
        vm.cancel = => @cancel?()
        
class ConfirmModal_link extends Modal
    constructor: (@message, @confirm, @cancel,@warn) ->
        super "confirm-", "html/confirm_Initr.html"

    define_vm: (vm) =>
        vm.message = @message
        vm.lang = lang.confirm_modal
        vm.warn = lang.initr_link_modal
        vm.submit_confirm = => @confirm?()
        vm.cancel = => @cancel?()
            
class ConfirmModal extends Modal
    constructor: (@message, @confirm, @cancel) ->
        super "confirm-", "html/confirm_modal.html"

    define_vm: (vm) =>
        vm.message = @message
        vm.lang = lang.confirm_modal
        vm.submit_confirm = => @confirm?()
        vm.cancel = => @cancel?()


class ConfirmModal_more extends Modal
    constructor: (@title,@message,@sd,@dview,@settings) ->
        super "confirm-", "html/confirm_vaildate_modal.html"
        @settings = new SettingsManager
    define_vm: (vm) =>
        vm.title = @title
        vm.message = @message
        vm.lang = lang.confirm_vaildate_modal
        vm.confirm = true
        vm.confirm_passwd = ""
        vm.submit = @submit
        vm.bottom = true
        vm.sysinit = @sysinit
        vm.recover = @recover
        vm.keypress_passwd = @keypress_passwd
        
    rendered: () =>
        super()
        $.validator.addMethod("same", (val, element) =>
            if @vm.confirm_passwd != 'passwd'
                return false
            else
                return true
        , "密码输入错误")

        $("form.passwd").validate(
            valid_opt(
                rules:
                    confirm_passwd:
                        required: true
                        maxlength: 32
                        same: true
                messages:
                    confirm_passwd:
                        required: "请输入正确的确认密码"
                        maxlength: "密码长度不能超过32个字符"))

    submit: () =>
        if @title == @vm.lang.btn_sysinit
            @sysinit()
        else if @title == @vm.lang.btn_recover
            @recover()

    keypress_passwd: (e) =>
        @submit() if e.which is 13    

    sysinit: () =>
        if $("form.passwd").validate().form()
            chain = new Chain()
            chain.chain => (new CommandRest(@dview.sd.host)).sysinit()
            @hide()
            show_chain_progress(chain, true).fail (data)=>
                @settings.removeLoginedMachine @dview.host
                @sd.close_socket()
                arr_remove sds, @sd
                setTimeout(@dview.switch_to_login_page, 2000)
             
    recover: () =>
        if $("form.passwd").validate().form()
            chain = new Chain()
            chain.chain => (new CommandRest(@dview.sd.host)).recover()
            @hide()
            show_chain_progress(chain, true).done (data)=>
                (new MessageModal_reboot(lang.maintainpage.finish_recover,@vm.bottom,@dview,@sd,@settings)).attach()
            .fail (data)=>
                console.log "error"
                console.log data
                
class ConfirmModal_scan extends Modal
    constructor: (@sd, @page, @title, @message, @fs) ->
        super "confirm-", "html/confirm_reboot_modal.html"
        
    define_vm: (vm) =>
        vm.lang = lang.confirm_reboot_modal
        vm.title = @title
        vm.message = @message
        vm.submit = @reboot
        vm.res = @fs

    reboot: () =>
        chain = new Chain()
        chain.chain => (new CommandRest(@sd.host)).reboot()
        @hide()
        show_chain_progress(chain, true).fail =>
            @sd.close_socket()
            arr_remove sds, @sd      
            
class ResDeleteModal extends Modal
    constructor: (prefix, @page, @res, @lang) ->
        super prefix, 'html/res_delete_modal.html'

    define_vm: (vm) =>
        vm.lang = @lang
        vm.res = @res
        vm.submit = @submit

    rendered: () =>
        $(".chosen").chosen()
        super()

    submit: () =>
        chain = @_submit($(opt).prop "value" for opt in $(".modal-body :selected"))
        @hide()
        show_chain_progress(chain).done =>
            @page.attach()

class SyncDeleteModal extends ResDeleteModal
    constructor: (@sd, page, res) ->
        super "sync-delete-", page, res, lang.confirm_sync_modal
        
    _submit: (real_failed_volumes) =>
        @page.frozen()
        chain = new Chain
        chain.chain($.map(real_failed_volumes, (v) => (=> (new SyncConfigRest(@sd.host)).sync_disable v)))
            .chain @sd.update("volumes")
        return chain
            
class RaidDeleteModal extends ResDeleteModal
    constructor: (@sd, page, res) ->
        super "raid-delete-", page, res, lang.raid_delete_modal

    _submit: (deleted) =>
        @page.frozen()
        chain = new Chain
        chain.chain($.map(deleted, (r) => (=> (new RaidRest(@sd.host)).delete r)))
            .chain @sd.update("raids")
        return chain

class RaidCreateDSUUI extends AvalonTemplUI
    constructor: (@sd, parent_selector, @enabled=['data','spare'], @on_quickmode=false) ->
        super "dsuui-", "html/raid_create_dsu_ui.html", parent_selector
        for dsu in @vm.data_dsus
            @watch_dsu_checked dsu

    define_vm: (vm) =>
        vm.lang = lang.dsuui
        vm.data_dsus = @_gen_dsus "data"
        vm.spare_dsus = @_gen_dsus "spare"
        vm.active_index = 0
        vm.on_quickmode = @on_quickmode
        vm.disk_checkbox_click = @disk_checkbox_click
        vm.dsu_checkbox_click = @dsu_checkbox_click
        vm.data_enabled  = 'data' in @enabled
        vm.spare_enabled = 'spare' in @enabled
        vm.disk_list = @disk_list

    dsu_checkbox_click: (e) =>
        e.stopPropagation()
        
    disk_list: (disks)=>
        if disks.info == "none"
            return "空盘"
        else
            return @_translate(disks.info)
        
    _translate: (obj) =>
        status = ''
        health = {'normal':'正常', 'down':'下线', 'failed':'损坏'}
        role = {'data':'数据盘', 'spare':'热备盘', 'unused':'未使用', 'kicked':'损坏'}
        
        $.each obj, (key, val) ->
            switch key
                when 'cap_sector'
                    status += '容量: ' + fattr.cap(val)+ '<br/>'
                when 'health'
                    status += '健康: ' + health[val] + '<br/>'
                when 'role'
                    status += '状态: ' + role[val] + '<br/>'
                when 'raid'
                    if val.length > 0
                        status += '阵列: ' + val + '<br/>'
                    else
                        status += '阵列: 无'
        return status
        
    active_tab: (dsu_location) =>
        for dsu, i in @vm.data_dsus
            if dsu.location is dsu_location
                @vm.active_index = i

    disk_checkbox_click: (e) =>
        e.stopPropagation()
        location = $(e.target).data "location"
        if location
            dsutype = $(e.target).data "dsutype"
            [dsus, opp_dsus] = if dsutype is "data"\
                then [@vm.data_dsus, @vm.spare_dsus]\
                else [@vm.spare_dsus, @vm.data_dsus]
            dsu = @_find_dsu dsus, location
            opp_dsu = @_find_dsu opp_dsus, location
            @_uncheck_opp_dsu_disks dsu, opp_dsu
            @_count_dsu_checked_disks dsu
            @_count_dsu_checked_disks opp_dsu

           ### if dsutype is "data"
                @_calculatechunk dsu
            else
                @_calculatechunk opp_dsu
            $("#dsuui").change()       ###

    watch_dsu_checked: (dsu) =>
        dsu.$watch 'checked', () =>
            for col in dsu.disks
                for disk in col
                    if not disk.avail
                        continue
                    disk.checked = dsu.checked
            opp_dsu = @_get_opp_dsu dsu
            @_uncheck_opp_dsu_disks dsu, opp_dsu
            @_count_dsu_checked_disks dsu
            @_count_dsu_checked_disks opp_dsu

           # @_calculatechunk dsu
            #$("#dsuui").change()

    _calculatechunk: (dsu) =>
        @_count_dsu_checked_disks dsu
        nr = dsu.count
        if nr <= 0
            return "64KB"
        else if nr == 1
            return "256KB"
        else
            ck = 512 / (nr - 1)
            if ck > 16 and ck <= 32
                return "32KB"
            else if ck > 32 and ck <= 64
                return "64KB"
            else if ck > 64 and ck <= 128
                return "128KB"
            else if ck > 128
                return "256KB"

    getchunk:() =>
        chunk_value = []
        for dsu in @vm.data_dsus
            chunk_value.push  @_calculatechunk(dsu)
        return chunk_value[0]

    _count_dsu_checked_disks: (dsu) =>
        count = 0
        for col in dsu.disks
            for disk in col
                if disk.checked
                    count += 1
        dsu.count = count

    _uncheck_opp_dsu_disks: (dsu, opp_dsu) =>
        for col in dsu.disks
            for disk in col
                if disk.checked
                    opp_disk = @_find_disk [opp_dsu], disk.$model.location
                    opp_disk.checked = false

    get_disks: (type="data") =>
        dsus = if type is "data" then @vm.data_dsus else @vm.spare_dsus
        @_collect_checked_disks dsus

    _collect_checked_disks: (dsus) =>
        disks = []
        for dsu in dsus
            for col in dsu.disks
                for disk in col
                    disks.push(disk.location) if disk.checked
        return disks

    check_disks: (disks, type="data") =>
        dsus = if type is "data" then @vm.data_dsus else @vm.spare_dsus
        disks = if $.isArray(disks) then disks else [disks]
        for dsu in dsus
            for col in dsu.disks
                for disk in col
                    for checked in disks
                        if disk.location is checked.location
                            disk.checked = true
        for dsu in dsus
            @_count_dsu_checked_disks dsu

    _find_disk: (dsus, location) =>
        for dsu in dsus
            for col in dsu.disks
                for disk in col
                    if disk.$model.location is location
                        return disk

    _find_dsu: (dsus, location) =>
        for dsu in dsus
            for col in dsu.disks
                for disk in col
                    if disk.$model.location is location
                        return dsu

    _get_opp_dsu: (dsu) =>
        opp_dsus = if dsu.data then @vm.spare_dsus else @vm.data_dsus
        for opp_dsu in opp_dsus
            if opp_dsu.location is dsu.location
                return opp_dsu

    _tabid: (tabid_prefix, dsu) =>
        "#{tabid_prefix}_#{dsu.location.replace('.', '_')}"

    _gen_dsus: (prefix) =>
        return ({location: dsu.location, tabid: @_tabid(prefix, dsu), checked: false,\
            disks: @_gen_dsu_disks(dsu), count: 0, data: prefix is 'data'} for dsu in @sd.dsus.items)

    _belong_to_dsu: (disk, dsu) =>
        disk.location.indexOf(dsu.location) is 0

    _update_disk_status: (location, dsu) =>
        for disk in @sd.disks.items
            if disk.location is location and @_belong_to_dsu(disk, dsu) and disk.raid is "" and disk.health isnt "failed" and disk.role is "unused"
                return true
        return false
    
    _update_disk_info: (location, dsu) =>
        info = []
        for disk in @sd.disks.items
            if disk.location is location and @_belong_to_dsu(disk, dsu)
                info = health:disk.health, cap_sector:disk.cap_sector, role:disk.role, raid:disk.raid
                return info
        
        'none'
        
    _gen_dsu_disks: (dsu) =>
        disks = []

        for i in [1..4]
            cols = []
            for j in [0...dsu.support_disk_nr/4]
                location = "#{dsu.location}.#{j*4+i}"
                o = location: location, avail: false, checked: false, offline: false, info: ""
                o.avail = @_update_disk_status(location, dsu)
                o.info = @_update_disk_info(location, dsu)
                cols.push o
            disks.push cols

        return disks

    rendered: () =>
        super()

class RaidSetDiskRoleModal extends Modal
    constructor: (@sd, @page) ->
        super "raid-set-disk-role-modal-",\
            "html/raid_set_disk_role_modal.html",\
            style: "min-width:670px;"
        @raid = null

    define_vm: (vm) =>
        vm.lang = lang.raid_set_disk_role_modal
        vm.raid_options = subitems @sd.raids.items, name:""
        vm.role = "global_spare"
        vm.submit = @submit
        vm.select_visible = false

        vm.$watch "role", =>
            vm.select_visible = if vm.role == "global_spare" then false else true

    rendered: () =>
        super()
        @dsuui = new RaidCreateDSUUI(@sd, "#dsuui", ['spare'])
        @dsuui.attach()
        @add_child @dsuui
        $("input:radio").uniform()
        $("#raid-select").chosen()

        $.validator.addMethod("min-spare-disks", (val, element) =>
            nr = @dsuui.get_disks("spare").length
            return if nr is 0 then false else true)

        $("form.raid").validate(
            valid_opt(
                rules:
                    "spare-disks-checkbox":
                        "min-spare-disks": true
                messages:
                    "spare-disks-checkbox":
                        "min-spare-disks": "至少需要1块热备盘"))

    submit: () =>
        raid = null
        if @vm.select_visible
            chosen = $("#raid-select")
            raid = chosen.val()
        @set_disk_role @dsuui.get_disks("spare"), @vm.role, raid

    set_disk_role: (disks, role, raid) =>
        chain = new Chain
        for disk in disks
            chain.chain @_each_set_disk_role(disk, role, raid)
        @hide()
        show_chain_progress(chain).done =>
            @page.attach()

    _each_set_disk_role: (disk, role, raid) =>
        return () => (new DiskRest @sd.host).set_disk_role disk, role, raid

class RaidCreateModal extends Modal
    constructor: (@sd, @page) ->
        super "raid-create-modal-", "html/raid_create_modal.html", style: "min-width:670px;"

    define_vm: (vm) =>
        vm.lang = lang.raid_create_modal
        vm.name = ""
        vm.level = "5"
        #vm.chunk = "64KB"
        vm.rebuild_priority = "low"
        vm.sync = false
        vm.submit = @submit

    rendered: () =>
        super()
        @dsuui = new RaidCreateDSUUI(@sd, "#dsuui")
        @dsuui.attach()
        @add_child @dsuui
        $("input:radio").uniform()
        $(".basic-toggle-button").toggleButtons()
        $("#sync").change =>
            @vm.sync = $("#sync").prop "checked"

        dsu = @prefer_dsu_location()
        [raids...] = (disk for disk in @sd.disks.items\
                                when disk.role is 'unused'\
                                and disk.location.indexOf(dsu) is 0)
        [cap_sector...] = (raid.cap_sector for raid in raids)
        total = []
        cap_sector.sort()
        for i in [0...cap_sector.length]
            count = 0
            for j in [0...cap_sector.length]
                if cap_sector[i] is cap_sector[j]
                    count++
            total.push([cap_sector[i],count])
            i+=count
            
        for k in [0...total.length]
            if total[k][1] >= 3
                [Raids...] = (disk for disk in raids\
                                when disk.cap_sector is total[k][0])
                for s in [0...3]
                    @dsuui.check_disks Raids[s]
                    @dsuui.active_tab dsu
                #@dsuui.check_disks Raids[3], "spare"
                break
                
        $.validator.addMethod("min-raid-disks", (val, element) =>
            level = parseInt @vm.level
            nr = @dsuui.get_disks().length
            if level is 5 and nr < 3
                return false
            else if level is 0 and nr < 1
                return false
            else if level is 1 and nr isnt 2
                return false
            else if level is 10 and nr%2 != 0  and nr > 0
                return false
            else
                return true
        ,(params, element) =>
            level = parseInt @vm.level
            nr = @dsuui.get_disks().length
            if level is 5 and nr < 3
                return "级别5阵列最少需要3块磁盘"
            else if level is 0 and nr < 1
                return "级别0阵列最少需要1块磁盘"
            else if level is 1 and nr != 2
                return "级别1阵列仅支持2块磁盘"
            else if level is 10 and nr%2 != 0 and nr > 0
                return "级别10阵列数据盘必须是偶数个"
        )
        $.validator.addMethod("spare-disks-support", (val, element) =>
            level = parseInt @vm.level
            nr = @dsuui.get_disks("spare").length
            if level is 0 and nr > 0
                return false
            else if level is 10 and nr > 0
                return false
            else
                return true
        ,(params, element) =>
            level = parseInt @vm.level
            nr = @dsuui.get_disks("spare").length
            if level is 0 and nr > 0
                return '级别0阵列不支持热备盘'
            else if level is 10 and nr > 0
                return '级别10阵列不支持热备盘'
        )
        $.validator.addMethod("min-cap-spare-disks", (val, element) =>
            level = parseInt @vm.level
            if level != 5
                return true
            map = {}
            for disk in @sd.disks.items
                map[disk.location] = disk

            spare_disks = (map[loc] for loc in @dsuui.get_disks("spare"))
            data_disks = (map[loc] for loc in @dsuui.get_disks())
            min_cap = Math.min.apply(null, (d.cap_sector for d in data_disks))
            for s in spare_disks
                if s.cap_sector < min_cap
                    return false
            return true
        , "热备盘容量太小"
        )
        
        $("form.raid").validate(
            valid_opt(
                rules:
                    name:
                        required: true
                        regex: "^[_a-zA-Z][-_a-zA-Z0-9]*$"
                        duplicated: @sd.raids.items
                        maxlength: 64
                    "raid-disks-checkbox":
                        "min-raid-disks": true
                        maxlength: 24
                    "spare-disks-checkbox":
                        "spare-disks-support": true
                        "min-cap-spare-disks": true
                messages:
                    name:
                        required: "请输入阵列名称"
                        duplicated: "阵列名称已存在"
                        maxlength: "阵列名称长度不能超过64个字母"
                    "raid-disks-checkbox":
                        maxlength: "阵列最多支持24个磁盘"))

    submit: () =>
        if $("form.raid").validate().form()
            @create(@vm.name, @vm.level, @dsuui.getchunk(), @dsuui.get_disks(),\
                @dsuui.get_disks("spare"), @vm.rebuild_priority, @vm.sync)

    create: (name, level, chunk, raid_disks, spare_disks, rebuild, sync) =>
        @page.frozen()
        raid_disks = raid_disks.join ","
        spare_disks = spare_disks.join ","
        chain = new Chain
        chain.chain(=> (new RaidRest(@sd.host)).create(name: name, level: level,\
            chunk: chunk, raid_disks: raid_disks, spare_disks:spare_disks,\
            rebuild_priority:rebuild, sync:sync, cache:''))
            .chain @sd.update("raids")

        @hide()
        show_chain_progress(chain).done =>
            @page.attach()

    count_dsu_disks: (dsu) =>
        return (disk for disk in @sd.disks.items\
                         when disk.role is 'unused'\
                         and disk.location.indexOf(dsu.location) is 0).length

    prefer_dsu_location: () =>
        for dsu in @sd.dsus.items
            if @count_dsu_disks(dsu) >= 3
                return dsu.location
        return if @sd.dsus.length then @sd.dsus.items[0].location else '_'

class VolumeDeleteModal extends ResDeleteModal
    constructor: (@sd, page, res) ->
        super "volume-delete-", page, res, lang.volume_delete_modal

    _submit: (deleted) =>
        @page.frozen()
        chain = new Chain
        chain.chain($.map(deleted, (v) => (=> (new VolumeRest(@sd.host)).delete v)))
            .chain @sd.update('volumes')
        return chain

class VolumeCreateModal extends Modal
    constructor: (@sd, @page) ->
        super "volume-create-modal-", "html/volume_create_modal.html"

    define_vm: (vm) =>
        @_settings = new (require("settings").Settings)
        vm.lang = lang.volume_create_modal
        vm.volume_name = ""
        vm.raid_options = @raid_options()
        vm.raid = $.extend {}, @sd.raids.items[0]
        vm.fattr_cap_usage = fattr.cap_usage
        vm.cap = sector_to_gb(vm.raid.cap_sector-vm.raid.used_cap_sector)
        vm.unit = "GB"
        vm.automap = false
        vm.initr_wwn = ""
        vm.submit = @submit

        vm.$watch "raid",=>
            if vm.unit == "MB"
                vm.cap = sector_to_mb(vm.raid.cap_sector-vm.raid.used_cap_sector)
            else if vm.unit =="GB"
                vm.cap = sector_to_gb(vm.raid.cap_sector-vm.raid.used_cap_sector)
            else
                vm.cap = sector_to_tb(vm.raid.cap_sector-vm.raid.used_cap_sector)
        vm.$watch "unit",=>
            if vm.unit == "MB"
                vm.cap = sector_to_mb(vm.raid.cap_sector-vm.raid.used_cap_sector)
            else if vm.unit =="GB"
                vm.cap = sector_to_gb(vm.raid.cap_sector-vm.raid.used_cap_sector)
            else
                vm.cap = sector_to_tb(vm.raid.cap_sector-vm.raid.used_cap_sector)

        vm.$watch "volume_name", =>
            vm.initr_wwn = "#{prefix_wwn}:#{vm.volume_name}"

    rendered: () =>
        super()
        $("input:radio").uniform()
        $(".basic-toggle-button").toggleButtons()
        $("#raid-select").chosen()
        $("#automap").change =>
            @vm.automap = $("#automap").prop "checked"
        chosen = $("#raid-select")
        chosen.change =>
            @vm.raid = $.extend {}, @sd.raids.get(chosen.val())
            $("form.volume").validate().element $("#cap")

        $.validator.addMethod("capacity", (val, elem) =>
            free_cap = @vm.raid.cap_sector - @vm.raid.used_cap_sector
            alloc_cap = cap_to_sector @vm.cap, @vm.unit
            if alloc_cap < mb_to_sector(1024)
                return false
            else if alloc_cap > free_cap
                return false
            else
                return true
        ,(params, elem) =>
            free_cap = @vm.raid.cap_sector - @vm.raid.used_cap_sector
            alloc_cap = cap_to_sector @vm.cap, @vm.unit
            if alloc_cap < mb_to_sector(1024)
                return "虚拟磁盘最小容量必须大于等于1024MB"
            else if alloc_cap > free_cap
                return "分配容量大于阵列的剩余容量"
        )
        
        $("form.volume").validate(
            valid_opt(
                rules:
                    name:
                        required: true
                        regex: '^[_a-zA-Z][-_a-zA-Z0-9]*$'
                        duplicated: @sd.volumes.items
                        maxlength: 64
                    capacity:
                        required: true
                        regex: "^\\d+(\.\\d+)?$"
                        capacity: true
                    wwn:
                        required: true
                        regex: '^(iqn.2013-01.net.zbx.initiator:)+[_a-zA-Z0-9]*$'
                        maxlength: 96  
                messages:
                    name:
                        required: "请输入虚拟磁盘名称"
                        duplicated: "虚拟磁盘名称已存在"
                        maxlength: "虚拟磁盘名称长度不能超过64个字母"
                    capacity:
                        required: "请输入虚拟磁盘容量"
                    wwn:
                        required: "请输入客户端名称"
                        maxlength: "客户端名称长度不能超过96个字母"))

    raid_options: () =>
        raids_availble = []
        raids = subitems @sd.raids.items, id:"", name:"", health: "normal"
        for i in raids
            if i.health == "normal"
                raids_availble.push i
        return raids_availble
        
    submit: () =>
        if $("form.volume").validate().form()
            @create(@vm.volume_name, @vm.raid.name, "#{@vm.cap}#{@vm.unit}", @vm.automap, @vm.initr_wwn)
            if @_settings.sync
                @sync(@vm.volume_name)

    create: (name, raid, cap, automap, wwn) =>
        @page.frozen()
        chain = new Chain
        chain.chain => (new VolumeRest(@sd.host)).create name: name, raid: raid, capacity: cap
        if automap
            if not @sd.initrs.get wwn
                for n in @sd.networks.items
                    if n.link and n.ipaddr isnt ""
                        portals = n.iface
                        break
                chain.chain => (new InitiatorRest(@sd.host)).create wwn:wwn, portals:portals
            chain.chain => (new InitiatorRest(@sd.host)).map wwn, name
        chain.chain @sd.update('volumes')

        @hide()
        show_chain_progress(chain).done =>
            @page.attach()

    sync: (name) =>
        @page.frozen()
        chain = new Chain()
        chain.chain => 
            (new SyncConfigRest(@sd.host)).sync_enable(name)
            
        @hide()
        show_chain_progress(chain).done =>
            @page.attach()

class InitrDeleteModal extends ResDeleteModal
    constructor: (@sd, page, res) ->
        super "initr-delete-", page, res, lang.initr_delete_modal

    _submit: (deleted) =>
        @page.frozen()
        chain = new Chain
        chain.chain($.map(deleted, (v) => (=> (new InitiatorRest(@sd.host)).delete v)))
        chain.chain @sd.update('initrs')
        return chain

class InitrCreateModal extends Modal
    constructor: (@sd, @page) ->
        super "initr-create-modal-", "html/initr_create_modal.html"
        @vm.show_iscsi = if @_iscsi.iScSiAvalable() and !@_settings.fc then true else false
        
    define_vm: (vm) =>
        @_settings = new (require("settings").Settings)
        @_iscsi = new IScSiManager
        vm.portals = @subitems()
        vm.lang = lang.initr_create_modal
        vm.initr_wwn = @_genwwn()
        vm.initr_wwpn = @_genwwpn()
        vm.show_iscsi = @show_iscsi
        
        vm.submit = @submit

        $(@sd.networks.items).on "updated", (e, source) =>
            @vm.portals = @subitems()

    subitems: () =>
        items = subitems @sd.networks.items,id:"",ipaddr:"",iface:"",netmask:"",type:"",checked:false
        removable = []
        if not @_able_bonding()
            for eth in items
                removable.push eth if eth.type isnt "bond-slave"
            return removable
        items

    _able_bonding: =>
        for eth in @sd.networks.items
            return false if (eth.type.indexOf "bond") isnt -1
        true

    _genwwn:  () ->
        wwn_prefix = 'iqn.2013-01.net.zbx.initiator'
        s1 = Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)
        s2 = Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)
        s3 = Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)
        "#{wwn_prefix}:#{s1}#{s2}#{s3}"

    _genwwpn:  () ->
        s = Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(3)
        for i in [1..7]
            s1 = Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(3)
            s = "#{s}:#{s1}"
        return s

    rendered: () =>
        super()
        $("form.initr").validate(
            valid_opt(
                rules:
                    wwpn:
                        required: true
                        regex: '^([0-9a-z]{2}:){7}[0-9a-z]{2}$'
                        duplicated: @sd.initrs.items
                        maxlength: 96
                    wwn:
                        required: true
                        regex: '^(iqn.2013-01.net.zbx.initiator:)(.*)$'
                        duplicated: @sd.initrs.items
                        maxlength: 96
                    'eth-checkbox':
                        required: !@_settings.fc
                        minlength: 1
                messages:
                    wwpn:
                        required: "请输入客户端名称"
                        duplicated: "客户端名称已存在"
                        maxlength: "客户端名称长度不能超过96个字母"
                    wwn:
                        required: "请输入客户端名称"
                        duplicated: "客户端名称已存在"
                        maxlength: "客户端名称长度不能超过96个字母"
                    'eth-checkbox': "请选择至少一个网口"))

    submit: () =>
        if $("form.initr").validate().form()
            portals = []
            for i in @vm.portals when i.checked
                portals.push i.$model.iface
            if @_settings.fc
                @create @vm.initr_wwpn, portals=""
            else
                @create @vm.initr_wwn, portals.join(",")

    create: (wwn, portals) =>
        @page.frozen()
        chain = new Chain
        chain.chain => (new InitiatorRest(@sd.host)).create wwn:wwn, portals:portals
        chain.chain @sd.update('initrs')

        @hide()
        show_chain_progress(chain).done =>
            @page.attach()

class VolumeMapModal extends Modal
    constructor: (@sd, @page, @initr) ->
        super "volume-map-modal-", "html/volume_map_modal.html"

    define_vm: (vm) =>
        vm.volumes = @subitems()
        vm.lang = lang.volume_map_modal
        vm.all_checked = false
        vm.submit = @submit

        vm.$watch "all_checked", =>
            for v in vm.volumes
                v.checked = vm.all_checked

    rendered: () =>
        super()
        $("form.map-volumes").validate(
            valid_opt(
                rules:
                    'volume-checkbox':
                        required: true
                        minlength: 1
                messages:
                    'volume-checkbox': "请选择至少一个虚拟磁盘"))
        
    submit: () =>
        if $("form.map-volumes").validate().form()
            selecteds = []
            for i in @vm.volumes when i.checked
                selecteds.push i.$model.name
            @map @initr.wwn, selecteds

    subitems: () =>
        volumes_available = []
        items = subitems @sd.spare_volumes(), id:"", name:"", health:"", cap_sector:"",\
             checked:false
        for i in items
            if i.health == "normal"
                volumes_available.push i
        
        return volumes_available

    map: (wwn, volumes) =>
        @page.frozen()
        chain = new Chain
        for volume in volumes
            chain.chain @_eachMap(wwn, volume)
        chain.chain @sd.update('initrs')

        @hide()
        show_chain_progress(chain).done =>
            @page.attach()
    
    _eachMap: (wwn, volume) =>
        return ()=> (new InitiatorRest @sd.host).map wwn, volume

class VolumeUnmapModal extends Modal
    constructor: (@sd, @page, @initr) ->
        super "volume-unmap-modal-", "html/volume_map_modal.html"

    define_vm: (vm) =>
        vm.volumes = @subitems()
        vm.lang = lang.volume_unmap_modal
        vm.all_checked = false
        vm.submit = @submit

        vm.$watch "all_checked", =>
            for v in vm.volumes
                v.checked = vm.all_checked

    rendered: () =>
        super()
        $("form.map-volumes").validate(
            valid_opt(
                rules:
                    'volume-checkbox':
                        required: true
                        minlength: 1
                messages:
                    'volume-checkbox': "请选择至少一个虚拟磁盘"))
        
    submit: () =>
        if $("form.map-volumes").validate().form()
            selecteds = []
            for i in @vm.volumes when i.checked
                selecteds.push i.$model.name
            @unmap @initr.wwn, selecteds

    subitems: () =>
        items = subitems @sd.initr_volumes(@initr), id:"", name:"", health:"", cap_sector:"",\
             checked:false

    unmap: (wwn, volumes) =>
        @page.frozen()
        chain = new Chain
        for volume in volumes
            chain.chain @_eachunmap(wwn,volume)
        chain.chain @sd.update('initrs')

        @hide()
        show_chain_progress(chain).done =>
            @page.attach()
     
    _eachunmap: (wwn,volume) =>
        return () => (new InitiatorRest(@sd.host)).unmap wwn, volume
        
class EthBondingModal extends Modal
    constructor: (@sd, @page) ->
        super "Eth-bonding-modal-", "html/eth_bonding_modal.html"

    define_vm: (vm) =>
        vm.lang = lang.eth_bonding_modal
        vm.options = [
          { key: "负载均衡模式", value: "balance-rr" }
          { key: "主备模式", value: "active-backup" }
        ]
        vm.submit = @submit
        vm.ip = ""
        vm.netmask = "255.255.255.0"

    rendered: =>
        super()

        $("#eth-bonding").chosen()

        Netmask = require("netmask").Netmask
        $.validator.addMethod("validIP", (val, element) =>
            regex = /^\d{1,3}(\.\d{1,3}){3}$/
            if not regex.test val
                return false
            try
                n = new Netmask @vm.ip, @vm.netmask
                return true
            catch error
                return false
        )
        $("form.eth-bonding").validate(
            valid_opt(
                rules:
                    ip:
                        required: true
                        validIP: true
                    netmask:
                        required: true
                        validIP: true
                messages:
                    ip:
                        required: "请输入IP地址"
                        validIP: "无效IP地址"
                    netmask:
                        required: "请输入子网掩码"
                        validIP: "无效子网掩码"))

    submit: =>
        if $("form.eth-bonding").validate().form()
            @page.frozen()
            @page.dview.reconnect = true
            chain = new Chain
            chain.chain =>
                selected = $("#eth-bonding").val()
                rest = new NetworkRest @sd.host
                rest.create_eth_bonding @vm.ip, @vm.netmask, selected

            @hide()
            show_chain_progress(chain, true).fail =>
                index = window.adminview.find_nav_index @page.dview.menuid
                window.adminview.remove_tab index if index isnt -1
                ###
                @page.settings.removeLoginedMachine @page.dview.host
                @sd.close_socket()
                arr_remove sds, @sd
                @page.attach()
                @page.dview.switch_to_login_page()
                ###

class FsCreateModal extends Modal
    constructor: (@sd, @page, @volname) ->
        super "fs-create-modal-", "html/fs_create_modal.html"

    define_vm: (vm) =>
        vm.mount_dirs = @subitems()
        vm.lang = lang.fs_create_modal
        vm.submit = @submit

    rendered: () =>
        super()
        $("form.fs").validate(
            valid_opt(
                rules:
                    'dir-checkbox':
                        required: true
                        maxlength: 1
                messages:
                    'dir-checkbox': "请选择一个目录作为挂载点"))

    subitems: () =>
        items = []
        used_names=[]

        for fs_o in @sd.filesystem.data
            used_names.push fs_o.name
        for i in [1..2]
            name = "myfs#{i}"
            if name in used_names
                o = path:"/share/vol#{i}", used:true, checked:false, fsname:name
            else
                o = path:"/share/vol#{i}", used:false, checked:false, fsname:name
            items.push o
        return items

    submit: () =>
        if $("form.fs").validate().form()
            dir_to_mount = ""

            for dir in @vm.mount_dirs when dir.checked
                dir_to_mount =  dir.fsname
            @enable_fs dir_to_mount

    enable_fs: (dir) =>
        if dir==''
            @hide()
            (new MessageModal(lang.volume_warning.over_max_fs)).attach()
        else
            @page.frozen()
            chain = new Chain()
            chain.chain(=> (new FileSystemRest(@sd.host)).create_cy dir, @volname)
                .chain @sd.update("filesystem")
            @hide()
            show_chain_progress(chain).done =>
                @page.attach()

class FsChooseModal extends Modal
    constructor: (@sd, @page, @fsname, @volname) ->
        super "fs-choose-modal-", "html/fs_choose_modal.html"

    define_vm: (vm) =>
        vm.filesystems = @subitems()
        vm.lang = lang.fs_choose_modal
        vm.submit = @submit

    rendered: () =>
        super()
        $("form.filesystems").validate(
            valid_opt(
                rules:
                    'fs-checkbox':
                        required: true
                        maxlength: 1
                messages:
                    'fs-checkbox': "请选择一个文件系统类型"))

    subitems: () =>
        items = []
        o = used:true, checked:false, type:"monfs", fsname:"视频文件系统"
        items.push o
        o = used:true, checked:false, type:"xfs", fsname:"通用文件系统"
        items.push o
        return items

    submit: () =>
        if $("form.filesystems").validate().form()
            fs_type = ""
            for filesystem in @vm.filesystems when filesystem.checked
                fs_type =  filesystem.type

            @enable_fs fs_type

    enable_fs: (fs_type) =>
        @page.frozen()
        chain = new Chain()
        chain.chain(=> (new FileSystemRest(@sd.host)).create @fsname, fs_type, @volname)
            .chain @sd.update("filesystem")
        @hide()
        show_chain_progress(chain).done =>
            @page.attach()

this.ConfirmModal = ConfirmModal
this.ConfirmModal_more = ConfirmModal_more
this.ConfirmModal_link = ConfirmModal_link
this.ConfirmModal_unlink = ConfirmModal_unlink
this.ConfirmModal_scan = ConfirmModal_scan
this.EthBondingModal = EthBondingModal
this.InitrCreateModal = InitrCreateModal
this.InitrDeleteModal = InitrDeleteModal
this.MessageModal = MessageModal
this.MessageModal_reboot = MessageModal_reboot
this.Modal = Modal
this.RaidCreateDSUUI = RaidCreateDSUUI
this.RaidSetDiskRoleModal = RaidSetDiskRoleModal
this.RaidCreateModal = RaidCreateModal
this.RaidDeleteModal = RaidDeleteModal
this.ResDeleteModal = ResDeleteModal
this.SyncDeleteModal = SyncDeleteModal
this.VolumeCreateModal = VolumeCreateModal
this.VolumeDeleteModal = VolumeDeleteModal
this.VolumeMapModal = VolumeMapModal
this.VolumeUnmapModal = VolumeUnmapModal
this.FsCreateModal = FsCreateModal
this.FsChooseModal = FsChooseModal