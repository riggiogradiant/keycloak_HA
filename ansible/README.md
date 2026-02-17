# Keycloak HA - Ansible Deployment

This directory contains Ansible playbooks, roles, and configurations for deploying Keycloak High Availability (HA) cluster across **multiple physical hosts**.

## 📁 Directory Structure

```
ansible/
├── ansible.cfg                    # Ansible configuration
├── inventory/
│   └── hosts.yml                  # Host inventory (multiregion-1, multiregion-2)
├── group_vars/
│   └── all.yml                    # Global variables (passwords, versions, etc.)
├── host_vars/
│   ├── multiregion-1.yml          # Variables for host 1 (10.11.5.71)
│   └── multiregion-2.yml          # Variables for host 2 (10.5.4.161)
├── playbooks/
│   ├── 00-verify-connectivity.yml # Phase 1: Verify connectivity & prerequisites
│   ├── 01-prepare-hosts.yml       # Phase 2: Install Docker, configure firewall
│   ├── 02-generate-certs.yml      # Phase 3: Generate SSL certificates
│   ├── 03-deploy-etcd.yml         # Phase 4: Deploy etcd cluster
│   ├── 04-deploy-patroni.yml      # Phase 5: Deploy PostgreSQL + Patroni
│   ├── 05-deploy-haproxy.yml      # Phase 6: Deploy HAProxy
│   ├── 06-deploy-keycloak.yml     # Phase 7: Deploy Keycloak
│   ├── 07-test-cluster.yml        # Phase 8: Test cluster health
│   └── 08-test-failover.yml       # Phase 9: Test failover (optional)
├── roles/                         # (To be created in later phases)
│   ├── docker-setup/
│   ├── firewall-setup/
│   ├── certificates/
│   ├── etcd/
│   ├── patroni/
│   ├── haproxy/
│   └── keycloak/
└── templates/                     # (To be created in later phases)
    ├── docker-compose-node.yml.j2
    ├── patroni.yml.j2
    ├── haproxy.cfg.j2
    └── env.j2
```

## 🚀 Quick Start

### Prerequisites

1. **Ansible installed** on your control machine (local laptop/workstation):
   ```bash
   # On Ubuntu/Debian
   sudo apt update
   sudo apt install ansible

   # On macOS
   brew install ansible

   # Verify installation
   ansible --version
   ```

2. **SSH access** to both target hosts:
   - multiregion-1: `ssh fhaas@10.11.5.71`
   - multiregion-2: `ssh tdx@10.5.4.161`
   - SSH keys already configured (passwordless access)

3. **Docker installed** on both target hosts (will be verified in Phase 1)

### Phase 1: Verify Connectivity

From the `ansible/` directory:

```bash
cd ansible

# Test connectivity to all hosts
ansible all -m ping

# Run full connectivity verification
ansible-playbook playbooks/00-verify-connectivity.yml
```

**Expected output**:
- ✅ All hosts reachable
- ✅ Network connectivity between nodes OK
- ✅ Docker and Docker Compose installed
- ✅ Required ports available

### Phase 2-9: Incremental Deployment

(These playbooks will be created in subsequent phases)

```bash
# Phase 2: Prepare hosts (Docker, firewall, directories)
ansible-playbook playbooks/01-prepare-hosts.yml

# Phase 3: Generate SSL certificates
ansible-playbook playbooks/02-generate-certs.yml

# Phase 4: Deploy etcd cluster
ansible-playbook playbooks/03-deploy-etcd.yml

# Phase 5: Deploy PostgreSQL + Patroni
ansible-playbook playbooks/04-deploy-patroni.yml

# Phase 6: Deploy HAProxy
ansible-playbook playbooks/05-deploy-haproxy.yml

# Phase 7: Deploy Keycloak
ansible-playbook playbooks/06-deploy-keycloak.yml

# Phase 8: Test cluster health
ansible-playbook playbooks/07-test-cluster.yml

# Phase 9: Test failover (optional, destructive)
ansible-playbook playbooks/08-test-failover.yml
```

## 📝 Configuration

### Inventory (`inventory/hosts.yml`)

Defines the 2 physical hosts and their roles:

```yaml
multiregion-1:
  ansible_host: 10.11.5.71
  ansible_user: fhaas
  # Roles: etcd, postgres (PRIMARY), haproxy, keycloak

multiregion-2:
  ansible_host: 10.5.4.161
  ansible_user: tdx
  # Roles: etcd, postgres (REPLICA), haproxy, keycloak
```

### Global Variables (`group_vars/all.yml`)

Contains passwords, versions, and configuration shared across all hosts:

```yaml
# Credentials (CHANGE FOR PRODUCTION!)
postgres_password: keycloak_secret
keycloak_admin_password: admin

# Docker image versions
keycloak_version: "26.0.0"
postgres_version: "15"
patroni_version: "3.2.2"

# Deployment directories
deployment_dir: /opt/keycloak_ha
```

**⚠️ SECURITY WARNING**: Change default passwords before production deployment!

### Host-Specific Variables (`host_vars/`)

Variables unique to each host (IPs, node names, etc.):

- `multiregion-1.yml`: Configuration for node 1
- `multiregion-2.yml`: Configuration for node 2

## 🔧 Key Differences from Single-Host Deployment

| Aspect | Single-Host (Docker Compose) | Multi-Host (Ansible) |
|--------|------------------------------|----------------------|
| **Network** | Docker bridge (`keycloak_net`) | Exposed ports + IP routing |
| **Service Discovery** | Container names | Direct IP addresses |
| **HAProxy DNS** | Docker DNS (127.0.0.11) | Static IPs in config |
| **Certificates** | localhost, 127.0.0.1 | Actual server IPs |
| **etcd Cluster** | Container names | Host IP addresses |
| **JGroups TCPPING** | Container names | Host IP addresses |
| **Deployment** | `docker compose up` | Ansible playbooks |

## 🧪 Testing

After deployment, verify cluster health:

```bash
# Check etcd cluster
ansible all -a "docker exec etcd-nodo1 etcdctl member list"

# Check PostgreSQL cluster
ansible all -a "docker exec postgres-nodo1 patronictl -c /etc/patroni/patroni.yml list"

# Check Keycloak cluster formation
ansible all -a "docker logs keycloak-nodo1 | grep 'cluster view' | tail -1"

# Access Keycloak UI
# https://10.11.5.71:8443 or https://10.5.4.161:8443
```

## 📚 Architecture

```
┌─────────────────────────────────┐     ┌─────────────────────────────────┐
│   multiregion-1 (10.11.5.71)    │     │   multiregion-2 (10.5.4.161)    │
├─────────────────────────────────┤     ├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │     │ ┌─────────────────────────────┐ │
│ │   etcd-nodo1                │ │◄────┤ │   etcd-nodo2                │ │
│ │   :2379, :2380              │ │     │ │   :2379, :2380              │ │
│ └─────────────────────────────┘ │     │ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │     │ ┌─────────────────────────────┐ │
│ │   postgres-nodo1 (PRIMARY)  │ │────►│ │   postgres-nodo2 (REPLICA)  │ │
│ │   + Patroni                 │ │     │ │   + Patroni                 │ │
│ │   :5432, :8008              │ │     │ │   :5432, :8008              │ │
│ └─────────────────────────────┘ │     │ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │     │ ┌─────────────────────────────┐ │
│ │   haproxy-nodo1             │ │     │ │   haproxy-nodo2             │ │
│ │   :5432, :7000              │ │     │ │   :5432, :7000              │ │
│ └─────────────────────────────┘ │     │ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │     │ ┌─────────────────────────────┐ │
│ │   keycloak-nodo1            │ │◄───►│ │   keycloak-nodo2            │ │
│ │   :8443, :7800 (JGroups)    │ │     │ │   :8443, :7800 (JGroups)    │ │
│ └─────────────────────────────┘ │     │ └─────────────────────────────┘ │
└─────────────────────────────────┘     └─────────────────────────────────┘
```

## 🔐 Security Considerations

**Current configuration is for DEVELOPMENT/TESTING**.

For production:

1. ✅ Change ALL passwords in `group_vars/all.yml`
2. ✅ Use proper SSL certificates (Let's Encrypt or internal CA)
3. ✅ Configure firewall rules (restrict inter-node traffic)
4. ✅ Use secrets management (Ansible Vault, HashiCorp Vault)
5. ✅ Enable PostgreSQL synchronous replication
6. ✅ Implement monitoring (Prometheus, Grafana)
7. ✅ Set up automated backups

## 📖 Documentation

- **Complete system documentation**: See `../SYSTEM_CONTEXT.md`
- **Original single-host setup**: See `../README.md`
- **Project context for AI**: See `../.github/instructions/context.instructions.md`

## 🆘 Troubleshooting

### Connectivity Issues

```bash
# Test SSH connectivity
ansible all -m ping

# Test network connectivity between nodes
ansible all -m shell -a "ping -c 2 <peer_ip>"

# Check firewall rules
ansible all -m shell -a "sudo firewall-cmd --list-all"  # CentOS/RHEL
ansible all -m shell -a "sudo ufw status"                # Ubuntu
```

### Docker Issues

```bash
# Check Docker status
ansible all -m shell -a "docker info"

# Check running containers
ansible all -m shell -a "docker ps"

# View logs
ansible all -m shell -a "docker logs <container_name>"
```

### Port Conflicts

```bash
# Check what's using a port
ansible all -m shell -a "sudo netstat -tulpn | grep <port>"
ansible all -m shell -a "sudo ss -tulpn | grep <port>"
```

## 🎯 Development Status

- ✅ **Phase 1**: Infrastructure setup (COMPLETED)
- ⏳ **Phase 2**: Host preparation (TODO)
- ⏳ **Phase 3**: Certificate generation (TODO)
- ⏳ **Phase 4**: etcd deployment (TODO)
- ⏳ **Phase 5**: PostgreSQL/Patroni deployment (TODO)
- ⏳ **Phase 6**: HAProxy deployment (TODO)
- ⏳ **Phase 7**: Keycloak deployment (TODO)
- ⏳ **Phase 8**: Testing (TODO)
- ⏳ **Phase 9**: Failover testing (TODO)

## 🤝 Contributing

When modifying configurations:

1. Update both `inventory/hosts.yml` and corresponding `host_vars/`
2. Test changes with `--check` flag first (dry-run)
3. Update this README.md with new procedures
4. Update `../SYSTEM_CONTEXT.md` with architectural changes

## 📜 License

Same as parent project (Keycloak HA).

---

**For complete technical details**: See [../SYSTEM_CONTEXT.md](../SYSTEM_CONTEXT.md)
