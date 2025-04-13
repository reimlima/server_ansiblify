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
        echo "    localhost:"
        echo "      ansible_connection: local"
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
- name: Configure hosts file
  ansible.builtin.copy:
    content: "{{ lookup('ansible.builtin.file', '/etc/hosts') }}"
    dest: /etc/hosts
    mode: '0644'
    owner: root
    group: root

- name: Configure fstab file
  ansible.builtin.copy:
    content: "{{ lookup('ansible.builtin.file', '/etc/fstab') }}"
    dest: /etc/fstab
    mode: '0644'
    owner: root
    group: root
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
    
    # Process selected modules
    for module in "${SELECTED_MODULES[@]}"; do
        echo "Processing module: $module"
        "process_$module"
        add_role "$module"
    done

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
