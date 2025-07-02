#!/bin/bash
# shellcheck disable=SC2129  # Multiple redirects are intentional in some places
# shellcheck disable=SC2034  # Variables might be used in future implementations

# Define output directory structure
BASE_DIR="server_config"
ROLES_DIR="$BASE_DIR/roles"
GROUP_VARS_DIR="$BASE_DIR/group_vars"
HOST_VARS_DIR="$BASE_DIR/host_vars"
INVENTORY_DIR="$BASE_DIR/inventory"
DRY_RUN=false
GENERATE_CONFIG=false

# Available modules
declare -A MODULES=(
    ["services"]="System services configuration"
    ["docker"]="Docker containers configuration"
    ["system"]="System configurations (hosts, fstab)"
    ["vm"]="Virtual machines configuration"
    ["ssh"]="SSH keys and configurations"
    ["users"]="User management"
    ["paths"]="Custom paths configuration"
    ["packages"]="Package management"
    ["commands"]="Custom commands"
)

# Function to create meta files for roles - Define this BEFORE create_role
create_role_meta() {
    local role_name=$1
    local meta_file="$ROLES_DIR/$role_name/meta/main.yml"
    
    cat > "$meta_file" << EOF
---
galaxy_info:
  author: Server Configuration Generator
  description: Auto-generated role for $role_name
  license: MIT
  min_ansible_version: "2.9"
  platforms:
    - name: Ubuntu
      versions:
        - all
  galaxy_tags: []
dependencies: []
EOF
}

# Function to create role structure
create_role() {
    local role_name=$1
    local role_dir="$ROLES_DIR/$role_name"
    
    mkdir -p "$role_dir"/{tasks,handlers,defaults,vars,files,templates,meta}
    
    # Initialize tasks/main.yml with a placeholder task
    cat > "$role_dir/tasks/main.yml" << EOF
---
- name: Placeholder task for $role_name
  ansible.builtin.debug:
    msg: "Role $role_name is being executed"
EOF

    # Initialize handlers/main.yml
    cat > "$role_dir/handlers/main.yml" << EOF
---
# Handlers for $role_name
EOF

    # Initialize defaults/main.yml with role-specific defaults
    cat > "$role_dir/defaults/main.yml" << EOF
---
# Default variables for $role_name
${role_name}_enabled: true
EOF

    # Initialize vars/main.yml
    cat > "$role_dir/vars/main.yml" << EOF
---
# Variables for $role_name
EOF

    create_role_meta "$role_name"
}

# Function to create directory structure
create_directory_structure() {
    mkdir -p "$BASE_DIR"/{roles,group_vars,inventory}
    
    # Get primary IP address
    PRIMARY_IP=$(hostname -I | awk '{print $1}')
    
    # Create main playbook
    {
        echo "---"
        echo "- name: Server Configuration"
        echo "  hosts: all"
        echo "  become: true"
        echo "  gather_facts: true"
        echo "  roles: []"
    } > "$BASE_DIR/site.yml"
    
    # Create inventory file
    {
        echo "---"
        echo "all:"
        echo "  hosts:"
        echo "    $PRIMARY_IP:"
        echo "      ansible_connection: ssh"
        echo "      ansible_python_interpreter: /usr/bin/python3"
    } > "$BASE_DIR/inventory/hosts"
}

# Function to add role to main playbook
add_role() {
    local role_name=$1
    local temp_file
    if ! temp_file=$(mktemp) ; then
        echo "Error: Failed to create temporary file"
        return 1
    fi
    
    # Read the current content of site.yml
    if [ -f "$BASE_DIR/site.yml" ]; then
        # If this is the first role, replace the empty roles list
        if grep -q "roles: \[\]" "$BASE_DIR/site.yml"; then
            sed "s/roles: \[\]/roles:\n    - $role_name/" "$BASE_DIR/site.yml" > "$temp_file"
        else
            # Otherwise, append the new role
            awk -v role="$role_name" '
                /^  roles:/ {
                    print $0
                    print "    - " role
                    next
                }
                /^    -/ {
                    print $0
                    next
                }
                { print $0 }
            ' "$BASE_DIR/site.yml" > "$temp_file"
        fi
        mv "$temp_file" "$BASE_DIR/site.yml"
    fi
}

# Function to create ansible-lint configuration
create_lint_config() {
    cat > "$BASE_DIR/.ansible-lint" << 'EOF'
---
skip_list:
  - yaml[line-length]  # Skip line length checks

warn_list:  # Items in warn_list will only generate warnings
  - yaml[truthy]
  - command-instead-of-module
  - no-changed-when

use_default_rules: true

# Enable offline mode
offline: true

# Set maximum line length for documentation (not code)
max_line_length: 160

# Exclude files
exclude_paths:
  - .cache/
  - .git/
EOF
}

show_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --all                Generate complete configuration"
    echo "  --dry-run           Test the generated playbook without making changes"
    echo "  -h, --help           Show this help message"
    echo "Available modules:"
    for key in "${!MODULES[@]}"; do
        echo "  --${key}"
        echo "      ${MODULES[$key]}"
    done
}

check_dependencies() {
    local missing_deps=()
    
    # Check for ansible
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        missing_deps+=("ansible")
    fi
    
    # Check for ansible-lint if we want to use it
    if ! command -v ansible-lint >/dev/null 2>&1; then
        missing_deps+=("ansible-lint")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Error: Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        echo "Please install them using:"
        echo "  sudo apt install ${missing_deps[*]}"
        exit 1
    fi
}

# Place this BEFORE the test_playbook function
validate_playbook_structure() {
    local playbook_dir="$1"
    
    # Check if site.yml exists and is readable
    if [ ! -r "$playbook_dir/site.yml" ]; then
        echo "Error: site.yml not found or not readable"
        return 1
    fi
    
    # Check if roles directory exists
    if [ ! -d "$playbook_dir/roles" ]; then
        echo "Error: roles directory not found"
        return 1
    fi
    
    return 0
}

test_playbook() {
    local playbook_dir="$1"
    local return_code=0
    
    echo "Running playbook tests..."
    echo "-------------------------"
    
    # Install required collections quietly
    echo "Installing required collections..."
    {
        ansible-galaxy collection install -r "$playbook_dir/requirements.yml" --force 1>/dev/null 2>&1
    } || {
        echo "Failed to install required collections"
        return 1
    }
    
    if ! validate_playbook_structure "$playbook_dir"; then
        return 1
    fi
    
    # Run ansible-playbook syntax check first
    echo "Validating playbook syntax..."
    if ! ansible-playbook -i "$playbook_dir/inventory/hosts" "$playbook_dir/site.yml" --syntax-check; then
        return 1
    fi
    
    # Run ansible-lint if available
    if command -v ansible-lint >/dev/null 2>&1; then
        echo "Running ansible-lint..."
        if ! ansible-lint "$playbook_dir/site.yml"; then
            return_code=1
        fi
    fi
    
    # Run ansible-playbook in check mode
    echo "Running ansible-playbook in check mode..."
    if ! ansible-playbook -i "$playbook_dir/inventory/hosts" "$playbook_dir/site.yml" --check --diff; then
        return_code=1
    fi
    
    return $return_code
}

# Process functions
process_paths() {
    create_role "paths"
    local tasks_file="$ROLES_DIR/paths/tasks/main.yml"
    
    cat > "$tasks_file" << 'EOF'
---
- name: Get root directories
  ansible.builtin.find:
    paths: /
    file_type: directory
    depth: 0
  register: root_dirs

- name: Filter system directories
  ansible.builtin.set_fact:
    custom_paths: "{{ root_dirs.files |
                     map(attribute='path') |
                     select('regex', '^(?!/($|etc|var|bin|boot|dev|lib|lib64|media|mnt|opt|proc|root|run|sbin|srv|sys|tmp|usr|home)).*') |
                     list }}"

- name: Ensure custom paths exist
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    mode: '0755'
    owner: root
    group: root
  loop: "{{ custom_paths }}"
  when: custom_paths | length > 0
EOF
}

process_users() {
    create_role "users"
    local tasks_file="$ROLES_DIR/users/tasks/main.yml"
    
    cat > "$tasks_file" << 'EOF'
---
- name: Get system users
  ansible.builtin.getent:
    database: passwd
  register: user_list

- name: Ensure required users exist
  ansible.builtin.user:
    name: "{{ item.key }}"
    state: present
  loop: "{{ user_list.ansible_facts.getent_passwd | dict2items }}"
  when:
    - item.value.1 is number
    - item.value.1 >= 1000
    - item.value.1 != 65534
EOF
}

# Add other process_* functions here...
process_services() {
    create_role "services"
    local tasks_file="$ROLES_DIR/services/tasks/main.yml"
    
    cat > "$tasks_file" << 'EOF'
---
- name: Get running services
  ansible.builtin.service_facts:
  register: service_facts

- name: Configure system services
  ansible.builtin.systemd:
    name: "{{ item }}"
    enabled: true
    state: started
  loop: >-
    {{
      service_facts.ansible_facts.services |
      dict2items |
      selectattr('value.state', 'eq', 'running') |
      map(attribute='key') |
      select('regex', '^(?!systemd|dbus|system|network|cron|ssh).*\.service$') |
      list
    }}
  when: service_facts.ansible_facts.services is defined
EOF
}

process_docker() {
    create_role "docker"
    local tasks_file="$ROLES_DIR/docker/tasks/main.yml"
    
    cat > "$tasks_file" << 'EOF'
---
- name: Remove conflicting packages
  ansible.builtin.apt:
    name:
      - containerd
      - docker.io
      - docker-compose
    state: absent
  when: ansible_distribution == 'Ubuntu'

- name: Add Docker official GPG key
  ansible.builtin.apt_key:
    url: https://download.docker.com/linux/ubuntu/gpg
    state: present
  when: ansible_distribution == 'Ubuntu'

- name: Add Docker repository
  ansible.builtin.apt_repository:
    repo: "deb [arch={{ ansible_architecture }}] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
    state: present
    update_cache: true
  when: ansible_distribution == 'Ubuntu'

- name: Install Docker CE
  ansible.builtin.apt:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-buildx-plugin
      - docker-compose-plugin
    state: present
    update_cache: true
  when: ansible_distribution == 'Ubuntu'

- name: Deploy Docker Compose configuration
  ansible.builtin.template:
    src: docker-compose.yml.j2
    dest: /opt/docker/docker-compose.yml
    mode: '0644'
    owner: root
    group: root
    backup: true
  when: docker_info.containers is defined
EOF
}

process_system() {
    create_role "system"
    local tasks_file="$ROLES_DIR/system/tasks/main.yml"
    cat > "$tasks_file" << 'EOF'
---
- name: Copy all exported system files
  ansible.builtin.copy:
    src: "{{ item }}"
    dest: "/etc/{{ item | basename }}"
    owner: root
    group: root
    mode: '0644'
  with_fileglob:
    - "{{ role_path }}/files/*"
  ignore_errors: true

- name: Copy all exported system directories
  ansible.builtin.copy:
    src: "{{ item }}"
    dest: "/etc/{{ item | basename }}"
    owner: root
    group: root
    mode: '0755'
  with_fileglob:
    - "{{ role_path }}/files/*/"
  ignore_errors: true
EOF
}

process_vm() {
    create_role "vm"
    local tasks_file="$ROLES_DIR/vm/tasks/main.yml"
    
    cat > "$tasks_file" << 'EOF'
---
- name: Ensure required packages are installed
  ansible.builtin.apt:
    name:
      - qemu-kvm
      - libvirt-daemon-system
    state: present
    update_cache: true

- name: Get virtual machines list
  ansible.builtin.command: virsh list --all --name
  register: vm_list
  changed_when: false
  when: ansible_facts.packages['qemu-kvm'] is defined or
        ansible_facts.packages['libvirt-daemon-system'] is defined

- name: Ensure virtual machines are running
  community.libvirt.virt:
    name: "{{ item }}"
    state: running
  loop: "{{ vm_list.stdout_lines | select('string') | list }}"
  when:
    - vm_list.stdout_lines is defined
    - vm_list.stdout_lines | length > 0
EOF
}

process_ssh() {
    create_role "ssh"
    local tasks_file="$ROLES_DIR/ssh/tasks/main.yml"
    
    cat > "$tasks_file" << 'EOF'
---
- name: Get system users
  ansible.builtin.getent:
    database: passwd
  register: user_list

- name: Check .ssh directories
  ansible.builtin.stat:
    path: "{{ item.value.4 }}/.ssh"
  loop: "{{ user_list.ansible_facts.getent_passwd | dict2items }}"
  when: item.value.4 is match('^/home/.*|^/root$')
  register: ssh_dirs

- name: Set users with .ssh directories
  ansible.builtin.set_fact:
    ssh_users: "{{ ssh_dirs.results |
                   selectattr('stat.exists', 'defined') |
                   selectattr('stat.exists') |
                   map(attribute='item.key') |
                   list }}"

- name: Process SSH configurations for users
  ansible.builtin.include_tasks: user_ssh.yml
  loop: "{{ ssh_users }}"
  loop_control:
    loop_var: username
  when: ssh_users | length > 0
EOF

    # Create user_ssh.yml for individual user processing
    local user_tasks_file="$ROLES_DIR/ssh/tasks/user_ssh.yml"
    cat > "$user_tasks_file" << 'EOF'
---
- name: Find SSH files for user
  ansible.builtin.find:
    paths: "{{ user_list.ansible_facts.getent_passwd[username].4 }}/.ssh"
    file_type: file
    patterns:
      - "authorized_keys"
      - "config"
      - "id_*"
      - "known_hosts"
  register: ssh_files

- name: Copy SSH files for user
  ansible.builtin.copy:
    src: "{{ item.path }}"
    dest: "{{ item.path }}"
    mode: "{{ item.path | basename | regex_search('pub$') | ternary('0644', '0600') }}"
    owner: "{{ username }}"
    group: "{{ user_list.ansible_facts.getent_passwd[username].3 }}"
    remote_src: true
  loop: "{{ ssh_files.files }}"
  when: ssh_files.files | length > 0
EOF
}

process_packages() {
    create_role "packages"
    local tasks_file="$ROLES_DIR/packages/tasks/main.yml"
    
    cat > "$tasks_file" << 'EOF'
---
- name: Get installed APT packages
  ansible.builtin.command: dpkg-query -f '${binary:Package}\n' -W
  register: apt_packages_raw
  changed_when: false

- name: Ensure APT packages are installed
  ansible.builtin.apt:
    name: "{{ item }}"
    state: present
  loop: "{{ apt_packages_raw.stdout_lines | select('string') | list }}"
  when: apt_packages_raw.stdout_lines | length > 0

- name: Get installed NPM packages
  ansible.builtin.command: npm list -g --depth=0
  register: npm_packages_raw
  changed_when: false

- name: Ensure NPM packages are installed
  community.general.npm:
    name: "{{ item }}"
    global: true
    state: present
  loop: "{{ npm_packages_raw.stdout_lines[1:] | select('string') | list }}"
  when: npm_packages_raw.stdout_lines[1:] | length > 0

- name: Get installed PIP packages
  ansible.builtin.command: pip list --format=freeze
  register: pip_packages_raw
  changed_when: false

- name: Ensure PIP packages are installed
  ansible.builtin.pip:
    name: "{{ item }}"
    state: present
  loop: "{{ pip_packages_raw.stdout_lines | select('string') | list }}"
  when: pip_packages_raw.stdout_lines | length > 0
EOF
}

process_commands() {
    create_role "commands"
    local tasks_file="$ROLES_DIR/commands/tasks/main.yml"
    
    cat > "$tasks_file" << 'EOF'
---
- name: Ensure custom commands are present
  ansible.builtin.copy:
    src: "{{ item }}"
    dest: /usr/local/bin/
    mode: '0755'
    owner: root
    group: root
  loop: "{{ lookup('ansible.builtin.pipe', 'find /usr/local/bin -type f -executable').split() }}"
  when: item != ""
EOF
}

# Function to generate requirements file
generate_requirements() {
    local base_dir="$1"
    
    # Create requirements.yml for any external roles/collections
    cat > "$base_dir/requirements.yml" << EOF
---
collections:
  - community.general
  - ansible.posix
  - community.docker
  - ansible.utils

roles: []
EOF
}

# Add this function to check and create default variables
generate_default_vars() {
    local base_dir="$1"
    
    cat > "$base_dir/group_vars/all.yml" << EOF
---
# Default variables for all hosts
ansible_python_interpreter: /usr/bin/python3
ansible_become: true
ansible_become_method: sudo

# Default paths
default_mode: '0755'
default_owner: root
default_group: root

# Default settings
always_run_handlers: true
collect_facts: true
EOF
}

# Generate dotfiles role tasks/main.yml
process_dotfiles() {
    local tasks_file="$ROLES_DIR/dotfiles/tasks/main.yml"
    mkdir -p "$(dirname "$tasks_file")"
    cat > "$tasks_file" << 'EOF'
---
- name: Get exported dotfile user directories
  ansible.builtin.find:
    paths: "{{ role_path }}/files"
    file_type: directory
    depth: 1
  register: dotfile_user_dirs

- name: Copy dotfiles for each user
  ansible.builtin.copy:
    src: "{{ item.1 }}"
    dest: "/home/{{ item.0 }}/{{ item.1 | basename }}"
    owner: "{{ item.0 }}"
    group: "{{ item.0 }}"
    mode: preserve
  with_subelements:
    - "{{ dotfile_user_dirs.files | map(attribute='path') | map('basename') | list }}"
    - "{{ lookup('fileglob', role_path + '/files/' + item + '/.*', wantlist=True) }}"
  loop_control:
    label: "{{ item.0 }}/{{ item.1 | basename }}"
EOF
}

# Generate completions role tasks/main.yml
process_completions() {
    local tasks_file="$ROLES_DIR/completions/tasks/main.yml"
    mkdir -p "$(dirname "$tasks_file")"
    cat > "$tasks_file" << 'EOF'
---
- name: Copy completions to /etc/bash_completion.d
  ansible.builtin.copy:
    src: "etc_bash_completion.d/{{ item | basename }}"
    dest: "/etc/bash_completion.d/{{ item | basename }}"
    owner: root
    group: root
    mode: '0644'
  with_fileglob:
    - "{{ role_path }}/files/etc_bash_completion.d/*"
  ignore_errors: true

- name: Copy completions to /usr/share/bash-completion/completions
  ansible.builtin.copy:
    src: "usr_share_bash_completion_completions/{{ item | basename }}"
    dest: "/usr/share/bash-completion/completions/{{ item | basename }}"
    owner: root
    group: root
    mode: '0644'
  with_fileglob:
    - "{{ role_path }}/files/usr_share_bash_completion_completions/*"
  ignore_errors: true
EOF
}

# Update services role tasks/main.yml to handle systemd units and enablement
process_services_playbook() {
    local tasks_file="$ROLES_DIR/services/tasks/main.yml"
    mkdir -p "$(dirname "$tasks_file")"
    cat > "$tasks_file" << 'EOF'
---
- name: Copy custom systemd unit files
  ansible.builtin.copy:
    src: "systemd/{{ item | basename }}"
    dest: "/etc/systemd/system/{{ item | basename }}"
    owner: root
    group: root
    mode: '0644'
  with_fileglob:
    - "{{ role_path }}/files/systemd/*.service"
  register: systemd_unit_copy

- name: Reload systemd if unit files changed
  ansible.builtin.systemd:
    daemon_reload: true
  when: systemd_unit_copy is changed

- name: Enable exported systemd services
  ansible.builtin.systemd:
    name: "{{ item | basename }}"
    enabled: true
  with_fileglob:
    - "{{ role_path }}/files/systemd/multi-user.target.wants/*.service"
EOF
}

# Update validate_yaml function with proper bash syntax
validate_yaml() {
    local file="$1"
    if [ ! -s "$file" ]; then
        echo "Error: $file is empty"
        return 1
    fi
    
    if ! grep -q "^---" "$file"; then
        echo "Error: $file is missing YAML document start marker (---)"
        return 1
    fi
    
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
            echo "Error: $file contains invalid YAML syntax"
            return 1
        fi
    fi
    return 0
}

# Add a function to clean up temporary files
cleanup_temp_files() {
    local exit_code=$?
    find /tmp -type f -name "tmp.*" -user "$(id -u)" -delete 2>/dev/null || true
    exit "$exit_code"
}

# === BEGIN REWRITE: EXPORT PHASE ===

# Export system files (e.g., /etc/hosts, /etc/fstab)
export_system_files() {
    local system_files=(/etc/hosts /etc/fstab)
    local dest_dir="$ROLES_DIR/system/files"
    mkdir -p "$dest_dir"
    for file in "${system_files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "$dest_dir/$(basename "$file")"
        fi
    done
}

# Export SSH keys/configs for all real users
export_ssh_files() {
    local dest_dir="$ROLES_DIR/ssh/files"
    mkdir -p "$dest_dir"
    # Get all users with home directories in /home or /root
    awk -F: '($3>=1000 && $3!=65534) || $1=="root" {print $1":"$6}' /etc/passwd | while IFS=: read -r user home; do
        if [ -d "$home/.ssh" ]; then
            mkdir -p "$dest_dir/$user"
            cp -a "$home/.ssh/." "$dest_dir/$user/"
        fi
    done
}

# Export custom scripts from /usr/local/bin
export_custom_scripts() {
    local src_dir="/usr/local/bin"
    local dest_dir="$ROLES_DIR/commands/files"
    mkdir -p "$dest_dir"
    find "$src_dir" -maxdepth 1 -type f -executable -exec cp {} "$dest_dir/" \;
}

# Export package lists
export_package_lists() {
    local dest_dir="$ROLES_DIR/packages/files"
    mkdir -p "$dest_dir"
    # APT packages
    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='${binary:Package}\n' > "$dest_dir/apt_packages.txt"
    fi
    # pip packages
    if command -v pip >/dev/null 2>&1; then
        pip freeze > "$dest_dir/pip_packages.txt"
    fi
    # npm packages
    if command -v npm >/dev/null 2>&1; then
        npm list -g --depth=0 | awk -F ' ' '/──/ {print $2}' > "$dest_dir/npm_packages.txt"
    fi
}

# Export Docker Compose files (if any)
export_docker_compose() {
    local src_file="/opt/docker/docker-compose.yml"
    local dest_dir="$ROLES_DIR/docker/files"
    mkdir -p "$dest_dir"
    if [ -f "$src_file" ]; then
        cp "$src_file" "$dest_dir/docker-compose.yml"
    fi
}

# Export custom systemd unit files
export_systemd_units() {
    local dest_dir="$ROLES_DIR/services/files/systemd"
    mkdir -p "$dest_dir"
    # Copy all custom unit files
    find /etc/systemd/system/ -maxdepth 1 -type f -name '*.service' -exec cp {} "$dest_dir/" \;
    # Copy all symlinks from multi-user.target.wants and their targets
    local wants_dir="/etc/systemd/system/multi-user.target.wants"
    if [ -d "$wants_dir" ]; then
        mkdir -p "$dest_dir/multi-user.target.wants"
        for link in "$wants_dir"/*.service; do
            [ -e "$link" ] || continue
            # Copy the symlink itself
            cp -P "$link" "$dest_dir/multi-user.target.wants/"
            # Copy the target of the symlink if it's not already in dest_dir
            target_path=$(readlink -f "$link")
            if [ -f "$target_path" ] && [ ! -f "$dest_dir/$(basename "$target_path")" ]; then
                cp "$target_path" "$dest_dir/"
            fi
        done
    fi
}

# Export cron configurations
export_cron_configs() {
    local dest_dir="$ROLES_DIR/system/files/cron"
    mkdir -p "$dest_dir"
    # Copy crontab, cron.d, cron.daily, etc.
    [ -f /etc/crontab ] && cp /etc/crontab "$dest_dir/"
    for crondir in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly; do
        [ -d "$crondir" ] && cp -a "$crondir" "$dest_dir/"
    done
}

# Export SNMP configuration
export_snmp_configs() {
    local dest_dir="$ROLES_DIR/system/files/snmp"
    mkdir -p "$dest_dir"
    [ -d /etc/snmp ] && cp -a /etc/snmp/. "$dest_dir/"
}

# Export rsync configuration
export_rsync_configs() {
    local dest_dir="$ROLES_DIR/system/files/rsync"
    mkdir -p "$dest_dir"
    [ -f /etc/rsyncd.conf ] && cp /etc/rsyncd.conf "$dest_dir/"
    [ -f /etc/rsyncd.secrets ] && cp /etc/rsyncd.secrets "$dest_dir/"
}

# Export motd and motd scripts
export_motd_configs() {
    local dest_dir="$ROLES_DIR/system/files/motd"
    mkdir -p "$dest_dir"
    [ -f /etc/motd ] && cp /etc/motd "$dest_dir/"
    [ -d /etc/update-motd.d ] && cp -a /etc/update-motd.d/. "$dest_dir/"
}

# Export NTP configuration
export_ntp_configs() {
    local dest_dir="$ROLES_DIR/system/files/ntp"
    mkdir -p "$dest_dir"
    [ -f /etc/ntp.conf ] && cp /etc/ntp.conf "$dest_dir/"
    [ -d /etc/ntp ] && cp -a /etc/ntp/. "$dest_dir/"
}

# Export user dotfiles (excluding .ssh)
export_dotfiles() {
    local dest_base="$ROLES_DIR/dotfiles/files"
    mkdir -p "$dest_base"
    awk -F: '($3>=1000 && $3!=65534) || $1=="root" {print $1":"$6}' /etc/passwd | while IFS=: read -r user home; do
        [ -d "$home" ] || continue
        mkdir -p "$dest_base/$user"
        find "$home" -maxdepth 1 -mindepth 1 -name ".*" ! -name ".ssh" -exec cp -a {} "$dest_base/$user/" \;
    done
}

# Export system-wide completion files
export_completions() {
    local dest_etc="$ROLES_DIR/completions/files/etc_bash_completion.d"
    local dest_usr="$ROLES_DIR/completions/files/usr_share_bash_completion_completions"
    mkdir -p "$dest_etc" "$dest_usr"
    [ -d /etc/bash_completion.d ] && cp -a /etc/bash_completion.d/. "$dest_etc/"
    [ -d /usr/share/bash-completion/completions ] && cp -a /usr/share/bash-completion/completions/. "$dest_usr/"
}

# Export user account files
export_users() {
    local dest_dir="$ROLES_DIR/users/files"
    mkdir -p "$dest_dir"
    cp /etc/passwd /etc/group "$dest_dir/"
}

# === END EXPORT PHASE ===

# Function to add all roles in roles directory to site.yml
add_all_roles_to_playbook() {
    local playbook_file="$BASE_DIR/site.yml"
    local roles_list
    roles_list=$(find "$ROLES_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
    # Write playbook header
    {
        echo "---"
        echo "- name: Server Configuration"
        echo "  hosts: all"
        echo "  become: true"
        echo "  gather_facts: true"
        echo "  roles:"
        for role in $roles_list; do
            echo "    - $role"
        done
    } > "$playbook_file"
}

# Main script execution
SELECTED_MODULES=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            SELECTED_MODULES=("${!MODULES[@]}")
            GENERATE_CONFIG=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        --*)
            module="${1#--}"
            if [[ -n "${MODULES[$module]}" ]]; then
                SELECTED_MODULES+=("$module")
                GENERATE_CONFIG=true
            else
                echo "Unknown module: $module"
                show_usage
                exit 1
            fi
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    shift
done

# Check if we need to generate configuration
if [ "$GENERATE_CONFIG" = false ] && [ "$DRY_RUN" = true ]; then
    if [ -d "$BASE_DIR" ]; then
        echo "Testing existing configuration in $BASE_DIR"
    else
        echo "No existing configuration found in $BASE_DIR"
        echo "Please generate a configuration first using --all or specific modules"
        exit 1
    fi
elif [ "$GENERATE_CONFIG" = false ]; then
    show_usage
    exit 1
fi

# Create base structure and process modules only if we're generating config
if [ "$GENERATE_CONFIG" = true ]; then
    # Create base structure
    create_directory_structure
    
    # Create lint config
    create_lint_config
    
    # Generate requirements file
    generate_requirements "$BASE_DIR"
    
    # Generate default variables
    generate_default_vars "$BASE_DIR"
    
    # Export and playbook generation phase for selected modules
    for module in "${SELECTED_MODULES[@]}"; do
        echo "Processing module: $module"
        case $module in
            paths)
                export_paths && process_paths && add_role paths
                ;;
            users)
                export_users && process_users && add_role users
                ;;
            ssh)
                export_ssh_files && process_ssh && add_role ssh
                ;;
            docker)
                export_docker_compose && process_docker && add_role docker
                ;;
            packages)
                export_package_lists && process_packages && add_role packages
                ;;
            commands)
                export_custom_scripts && process_commands && add_role commands
                ;;
            services)
                # Run export functions independently and collect errors
                export_errors=()
                
                echo "  Exporting systemd units..."
                export_systemd_units || export_errors+=("systemd_units")
                
                # Report any export errors
                if [ ${#export_errors[@]} -gt 0 ]; then
                    echo "  Warning: Some exports failed: ${export_errors[*]}"
                fi
                
                process_services_playbook && add_role services
                ;;
            system)
                # Run all export functions independently and collect errors
                export_errors=()
                
                echo "  Exporting system files..."
                export_system_files || export_errors+=("system_files")
                
                echo "  Exporting cron configurations..."
                export_cron_configs || export_errors+=("cron_configs")
                
                echo "  Exporting SNMP configurations..."
                export_snmp_configs || export_errors+=("snmp_configs")
                
                echo "  Exporting rsync configurations..."
                export_rsync_configs || export_errors+=("rsync_configs")
                
                echo "  Exporting MOTD configurations..."
                export_motd_configs || export_errors+=("motd_configs")
                
                echo "  Exporting NTP configurations..."
                export_ntp_configs || export_errors+=("ntp_configs")
                
                # Report any export errors
                if [ ${#export_errors[@]} -gt 0 ]; then
                    echo "  Warning: Some exports failed: ${export_errors[*]}"
                fi
                
                process_system && add_role system
                ;;
            vm)
                process_vm && add_role vm
                ;;
            dotfiles)
                export_dotfiles && process_dotfiles && add_role dotfiles
                ;;
            completions)
                export_completions && process_completions && add_role completions
                ;;
        esac
    done

    # If all modules are selected, add all roles to playbook
    if [ ${#SELECTED_MODULES[@]} -eq ${#MODULES[@]} ]; then
        add_all_roles_to_playbook
    fi

    # Create ansible.cfg
    cat > "$BASE_DIR/ansible.cfg" << EOF
[defaults]
inventory = ./inventory/hosts
roles_path = ./roles
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml

[ssh_connection]
pipelining = True
EOF
fi

# If dry-run is enabled, test the playbook
if [ "$DRY_RUN" = true ]; then
    echo "Running dry-run tests..."
    check_dependencies
    
    if test_playbook "$BASE_DIR"; then
        echo "✅ All tests passed successfully!"
    else
        echo "❌ Some tests failed. Please review the output above."
        exit 1
    fi
fi

if [ "$GENERATE_CONFIG" = true ]; then
    echo "Ansible playbook structure generated in $BASE_DIR/"
fi

if [ "$DRY_RUN" = false ]; then
    echo "To test the playbook without making changes, run:"
    echo "  $0 --dry-run"
fi

# Add this at the end of the script:
set -euo pipefail
trap cleanup_temp_files EXIT
