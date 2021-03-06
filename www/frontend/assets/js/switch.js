
function loadWorkgroup() {
    cookie = Cookies.getJSON('vce');
    var workgroupName = cookie.workgroup;
    
    var url = baseUrl + 'access.cgi?method=get_workgroup_details';
    url += '&workgroup=' + workgroupName;
    fetch(url, {method: 'get', credentials: 'include'}).then(function(response) {
        response.json().then(function(data) {
            if (typeof data.error !== 'undefined') {
                return displayError(data.error.msg);
            }

            var workgroup = data.results[0];
            console.log(workgroup);
            
            var name = document.getElementById('workgroup_name');
            name.innerHTML = workgroup.name;

            var description = document.getElementById('workgroup_description');
            description.innerHTML = workgroup.description;

            var users = document.getElementById('workgroup_users');
            users.innerHTML = workgroup.users.join(', ');

            var switches = document.getElementById('workgroup_switches');
            switches.innerHTML = workgroup.switches.length;
        });
    });
}

function loadSwitches() {
    cookie = Cookies.getJSON('vce');
    var workgroupName = cookie.workgroup;
    
    var url = baseUrl + 'operational.cgi?method=get_workgroup_operational_status';
    url += '&workgroup=' + workgroupName;
    fetch(url, {method: 'get', credentials: 'include'}).then(function(response) {
        response.json().then(function(data) {
            if (typeof data.error !== 'undefined') {
                return displayError(data.error.msg);
            }

            var switches = data.results[0].workgroups;
            var switchNames = [];
            
            var table = document.getElementById("switch_table");
            table.innerHTML = '';
            
            for (var i = 0; i < switches.length; i++) {
                var row = table.insertRow(0);

                var sw = row.insertCell(0);
                sw.id = switches[i].name;
                sw.innerHTML = switches[i].name;
                switchNames.push(switches[i].name);
                
                var status = row.insertCell(1);
                status.innerHTML = switches[i].status;
                
                var vlan = row.insertCell(2);
                var vlans_up = switches[i].up_vlans;
                var vlans_dn = switches[i].total_vlans - switches[i].up_vlans;
                vlan.innerHTML = `▲ ${vlans_up} &nbsp;&nbsp; ▼ ${vlans_dn}`;
                
                var ports = row.insertCell(3);
                var ports_up = switches[i].up_ports;
                var ports_dn = switches[i].total_ports - switches[i].up_ports;
                ports.innerHTML = `▲ ${ports_up} &nbsp;&nbsp; ▼ ${ports_dn}`;
            }
            
            setHeader(switchNames);
            
            cookie.switches = switchNames;
            Cookies.set('vce', cookie);
        });
    });
}
