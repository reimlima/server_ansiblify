# Server Ansiblify

[![Bash](https://img.shields.io/badge/bash-5.0%2B-brightgreen.svg)](https://www.gnu.org/software/bash/)
[![ShellCheck](https://img.shields.io/badge/shellcheck-passing-brightgreen.svg)](https://www.shellcheck.net/)

A powerful Bash script that scans a Linux server and automatically generates an Ansible playbook based on its current configuration. The script analyzes various system components and creates a structured Ansible project ready for deployment.

## Features

- 🔍 Scans and analyzes server configuration
- 📦 Generates complete Ansible playbook structure
- 🛠️ Supports multiple system components:
  - Virtual Machines (KVM/QEMU)
  - System Configuration (hosts, fstab)
  - Custom Commands
  - User Management
  - SSH Configuration
  - Docker Installation
  - Package Management (APT, NPM, PIP)
  - Service Management
  - Custom Path Configuration

## Directory Structure

```
server_config/
├── filter_plugins/
├── group_vars/
├── host_vars/
├── inventory/
├── roles/
│   ├── commands/
│   │   └── tasks/
│   ├── docker/
│   │   └── tasks/
│   ├── packages/
│   │   └── tasks/
│   ├── paths/
│   │   └── tasks/
│   ├── services/
│   │   └── tasks/
│   ├── ssh/
│   │   └── tasks/
│   ├── system/
│   │   └── tasks/
│   ├── users/
│   │   └── tasks/
│   └── vm/
│       └── tasks/
└── site.yml
```

## Parameters

| Parameter    | Description                           | Mandatory | Example           |
|-------------|---------------------------------------|-----------|--------------------|
| `--all`     | Generate complete playbook            | No        | `--all`            |
| `--dry-run` | Test playbook without making changes  | No        | `--dry-run`        |
| `--vm`      | Process virtual machine configuration | No        | `--vm`             |
| `--system`  | Process system configuration          | No        | `--system`         |
| `--docker`  | Process Docker configuration          | No        | `--docker`         |
| `--ssh`     | Process SSH configuration             | No        | `--ssh`            |
| `--users`   | Process user accounts                 | No        | `--users`          |
| `--paths`   | Process custom paths                  | No        | `--paths`          |
| `--services`| Process system services               | No        | `--services`       |
| `--packages`| Process installed packages            | No        | `--packages`       |
| `--commands`| Process custom commands               | No        | `--commands`       |

## Usage Example

### Generate Playbook
```bash
bash server_ansiblify.sh --all
Processing module: vm
Processing module: system
Processing module: commands
Processing module: users
Processing module: ssh
Processing module: docker
Processing module: packages
Processing module: services
Processing module: paths
Ansible playbook structure generated in server_config/
To test the playbook without making changes, run:
  server_ansiblify.sh --dry-run
```

### Test Playbook (Dry Run)
```bash
bash server_ansiblify.sh --dry-run
Testing existing configuration in server_config
Running dry-run tests...
Running playbook tests...
[...]
✅ All tests passed successfully!
```

## Requirements

- Linux Server (primarily tested on Ubuntu 24.04+)
- Bash 5.2.21+
- Ansible Core 2.18.4+
- Python 3.13+

## Author

- [reimlima](https://github.com/reimlima)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
