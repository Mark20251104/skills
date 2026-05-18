# 常见服务日志路径与状态查询速查

供 tmux-pane skill 在远程诊断场景下快速定位日志和状态命令。路径以 Linux 默认安装为准，实际环境可能不同——找不到时优先用 `ps aux | grep <service>` 从进程命令行参数反推路径。

## 目录

- [Java 应用服务器](#java-应用服务器)
- [Web 服务器](#web-服务器)
- [Spring Boot / 通用 Java](#spring-boot--通用-java)
- [数据库](#数据库)
- [容器与编排](#容器与编排)
- [系统服务](#系统服务)
- [通用诊断命令](#通用诊断命令)

## Java 应用服务器

### WebLogic

```bash
# 进程
ps aux | grep weblogic | grep -v grep

# AdminServer 日志（base_domain 是常见默认名）
tail -f /home/weblogic/Oracle/Middleware/user_projects/domains/base_domain/servers/AdminServer/logs/AdminServer.log

# GC 日志（从 java 进程参数中 -Xloggc 反查）
ps -ef | grep weblogic | grep -oP '(?<=-Xloggc:)[^ ]+'

# 通用反查日志目录
ps -ef | grep weblogic | grep -oP '(?<=-Dweblogic\.Name=)[^ ]+'
```

### Tomcat

```bash
# 进程
ps aux | grep -i tomcat | grep -v grep

# 主日志
tail -f $CATALINA_HOME/logs/catalina.out

# 默认路径
tail -f /opt/tomcat/logs/catalina.out
tail -f /var/log/tomcat*/catalina.out

# 访问日志
tail -f $CATALINA_HOME/logs/localhost_access_log.*.txt
```

### JBoss / WildFly

```bash
ps aux | grep -E 'jboss|wildfly' | grep -v grep
tail -f /opt/wildfly/standalone/log/server.log
```

## Web 服务器

### Nginx

```bash
# 进程
ps aux | grep nginx | grep -v grep
systemctl status nginx

# 日志（含虚拟主机会更多）
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# 配置检查
nginx -t
```

### Apache HTTPD

```bash
systemctl status httpd      # RHEL / CentOS
systemctl status apache2    # Debian / Ubuntu

tail -f /var/log/httpd/access_log    # RHEL
tail -f /var/log/apache2/access.log  # Debian
```

## Spring Boot / 通用 Java

```bash
# 进程及启动参数
ps -ef | grep java | grep -v grep
jps -lv

# 从启动命令反查日志路径
ps -ef | grep <app-name> | grep -oP '(?<=-Dlogging\.file\.name=)[^ ]+'
ps -ef | grep <app-name> | grep -oP '(?<=--logging\.file\.path=)[^ ]+'

# 常见默认位置
tail -f /var/log/<app-name>/application.log
tail -f ./logs/spring.log
tail -f /opt/<app>/logs/*.log

# JVM 监控
jstat -gc <pid> 1000     # GC 实时
jmap -heap <pid>         # 堆概况
jstack <pid>             # 线程栈
```

## 数据库

### MySQL / MariaDB

```bash
systemctl status mysqld     # 或 mariadb
tail -f /var/log/mysqld.log
tail -f /var/log/mysql/error.log

# 慢查询
tail -f /var/log/mysql/slow.log

# 进程内连接
mysql -e "SHOW PROCESSLIST;"
```

### PostgreSQL

```bash
systemctl status postgresql
tail -f /var/log/postgresql/postgresql-*.log
tail -f /var/lib/pgsql/data/log/postgresql-*.log
```

### Redis

```bash
systemctl status redis
tail -f /var/log/redis/redis-server.log
redis-cli INFO
redis-cli MONITOR        # 实时命令监控（注意性能影响）
```

## 容器与编排

### Docker

```bash
docker ps                                # 运行中容器
docker logs -f <container>               # tail 容器日志
docker logs --tail 100 -f <container>    # 最近 100 行起 tail
docker stats                             # 资源监控
docker inspect <container>               # 详细配置
```

### Kubernetes

```bash
kubectl get pods -A
kubectl logs -f <pod> -n <namespace>
kubectl logs -f <pod> -c <container> --previous   # 上次崩溃前的日志
kubectl describe pod <pod>
kubectl top pods
```

## 系统服务

### systemd

```bash
systemctl status <service>
systemctl is-active <service>
journalctl -u <service> -f                # 实时跟随
journalctl -u <service> --since "1 hour ago"
journalctl -u <service> -p err            # 仅错误级别
```

### supervisor

```bash
supervisorctl status
supervisorctl tail -f <program>
tail -f /var/log/supervisor/<program>.log
```

## 通用诊断命令

```bash
# 端口监听
ss -tlnp | grep <port>
netstat -tlnp | grep <port>
lsof -i :<port>

# 找出某进程打开的文件（含日志文件路径）
lsof -p <pid> | grep -E 'log|LOG'

# 找进程占用资源
top -p <pid>
htop -p <pid>

# 磁盘 / 内存
df -h
free -h
du -sh /var/log/*

# 网络连通性
curl -v http://localhost:<port>/health
nc -zv <host> <port>
```

## 路径反查的通用思路

不知道日志在哪时按此顺序排查：

1. **`systemctl status <service>`** 顶部会显示主 PID 和 cgroup
2. **`ps -ef | grep <service>`** 启动参数中常含 `-Dlog.dir=` 或 `--log-file=`
3. **`lsof -p <pid> | grep log`** 直接列出该进程当前打开的所有日志文件
4. **`journalctl -u <service>`** systemd 接管的服务统一在 journal 中
5. **`/var/log/`** 系统标准位置兜底
