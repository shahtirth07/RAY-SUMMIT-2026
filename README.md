# Clockwork SDET Interview Crash Course

## Goal

This guide assumes **zero prior knowledge** of GPU infrastructure, Linux internals, networking, Kubernetes, distributed systems, NCCL, RDMA, Slurm, and SDET framework design.

The goal is not to make you an expert in one day. The goal is to make you able to:

- understand the major layers of the system
- explain what each layer does
- reason about failures
- know what tools and commands are used to inspect problems
- speak clearly about SDET design, performance testing, GPU clusters, and distributed workloads

---

# 1. The Full System You Need to Understand

```text
                        YOUR PYTHON TESTS
                              |
                            pytest
                              |
                            CI/CD
                     Jenkins / GitHub Actions
                              |
                  Cluster management layer
                   Kubernetes / Slurm
                              |
              +---------------+---------------+
              |                               |
           Server 1                         Server 2
              |                               |
            Linux                           Linux
              |                               |
        Docker/Container                Docker/Container
              |                               |
          PyTorch Job                     PyTorch Job
              |                               |
             NCCL                            NCCL
              |                               |
       GPU 0 GPU 1 GPU 2              GPU 0 GPU 1 GPU 2
              |                               |
         PCIe / NVLink                  PCIe / NVLink
              |                               |
             NIC -------- NETWORK ----------- NIC
                           |
                   Ethernet / RoCE
                    or InfiniBand
                           |
                          RDMA
```

An infrastructure SDET sits across this whole stack.

The job is not just to say a test failed. The job is to determine whether the failure is in:

```text
test code
application
container
Kubernetes
Linux
GPU
GPU driver
NCCL
PCIe
NVLink
NIC
RDMA
network
another machine
```

---

# 2. SDET Fundamentals From Zero

## What is testing?

Suppose we have:

```python
def add(a, b):
    return a + b
```

A test could be:

```python
def test_add():
    result = add(2, 3)
    assert result == 5
```

The basic testing flow is:

```text
SET UP something
        ↓
DO something
        ↓
OBSERVE result
        ↓
COMPARE with expected behavior
        ↓
CLEAN UP
```

A common shorthand is:

```text
Arrange
Act
Assert
```

Also called AAA.

---

# 3. Unit, Integration, and End-to-End Tests

## Unit test

Tests one function or one small piece of logic.

```python
def calculate_gpu_count(nodes, gpu_per_node):
    return nodes * gpu_per_node
```

```python
assert calculate_gpu_count(4, 8) == 32
```

No real GPU. No network. No Kubernetes.

Advantages:

- fast
- cheap
- deterministic
- easy to debug

## Integration test

Checks several components together.

Example:

```text
Python scheduler
      ↓
Kubernetes API
      ↓
Pod created
```

## End-to-end test

Tests the real workflow.

```text
Create cluster
↓
Deploy workload
↓
Train model
↓
Verify GPUs communicated
↓
Verify performance
↓
Destroy cluster
```

These are slower and more expensive, but much more realistic.

---

# 4. The Test Pyramid

```text
             /\
            /  \
           / E2E\
          /------\
         /Integration\
        /------------\
       /  Unit Tests  \
      /________________\
```

Typical rule:

- many unit tests
- fewer integration tests
- even fewer end-to-end tests

GPU infrastructure still needs real hardware testing because hardware and networking behavior cannot be fully mocked.

---

# 5. Positive, Negative, Boundary, Regression, Smoke

## Positive testing

Valid input should succeed.

```text
request 4 GPUs
cluster has 8
→ success
```

## Negative testing

Invalid input should fail gracefully.

```text
request 16 GPUs
cluster has 8
→ reject or queue job
```

## Boundary testing

If allowed GPU count is 1 to 8, test:

```text
0
1
8
9
```

Bugs often happen at boundaries.

## Regression testing

A bug is fixed. You add a test that reproduces the old bug so it can never silently return.

Example:

```text
32-GPU workload hangs after node restart
```

After fix, add a permanent test.

## Smoke testing

A quick check to answer:

> Is this build obviously broken?

Examples:

```text
Can cluster be reached?
Can GPUs be detected?
Can one workload run?
```

---

# 6. Performance, Stress, Scale, Reliability

## Performance testing

Not just:

```text
Did it succeed?
```

Also:

```text
How fast was it?
```

Metrics include:

- latency
- throughput
- bandwidth
- GPU utilization
- tokens per second
- samples per second
- job startup time

Example:

```text
Baseline NCCL AllReduce: 180 GB/s
New build: 130 GB/s
```

Functional result may still be PASS, but performance result is FAIL.

## Stress testing

Push beyond normal limits.

```text
100 jobs
500 jobs
1000 jobs
```

or:

```text
8 GPUs
64 GPUs
256 GPUs
```

Question:

> Where does the system break?

## Scale testing

See whether performance remains acceptable as system grows.

```text
1 node
2 nodes
4 nodes
8 nodes
32 nodes
```

## Reliability testing

Run for a long time or many repetitions.

```text
run
tear down
recreate
run
tear down
recreate
```

Possible bugs discovered:

- memory leaks
- resource leaks
- race conditions
- intermittent hardware failures
- timing issues

---

# 7. Flaky Tests

A flaky test behaves inconsistently.

```text
run 1 → pass
run 2 → pass
run 3 → fail
run 4 → pass
```

Possible causes:

- timing
- race conditions
- network latency
- shared state
- bad cleanup
- randomness
- test order dependency
- external systems
- resource exhaustion

Bad solution:

```text
retry until it passes
```

Better approach:

```text
capture logs
capture timing
capture environment state
identify nondeterminism
make test isolated
make test reproducible
```

---

# 8. Test Isolation

Test A must not break Test B.

Bad example:

```text
Test A creates record
Test B assumes database is empty
```

If B runs after A, B may fail.

Each test should manage its own state and cleanup.

---

# 9. Deterministic Testing

Same input should produce same result.

If randomness is needed, preserve the seed.

```python
import random
random.seed(42)
```

This lets you reproduce failures.

---

# 10. pytest Basics

Basic test:

```python
def test_add():
    result = 2 + 3
    assert result == 5
```

Run all tests:

```bash
pytest
```

Verbose:

```bash
pytest -v
```

One file:

```bash
pytest test_math.py
```

One test:

```bash
pytest test_math.py::test_add
```

---

# 11. pytest Fixtures

Fixtures provide setup and cleanup.

```python
import pytest

@pytest.fixture
def database():
    db = connect()

    yield db

    db.close()
```

Test:

```python
def test_user(database):
    result = database.get_user()
    assert result is not None
```

Mental model:

```text
before yield = setup
yield = resource given to test
after yield = cleanup
```

GPU cluster example:

```python
@pytest.fixture
def gpu_cluster():
    cluster = create_cluster()

    yield cluster

    destroy_cluster(cluster)
```

## Fixture scopes

Common scopes:

```text
function
class
module
package
session
```

Default is function scope.

Session scope means one shared resource for the full test session.

Tradeoff:

```text
faster
but
less isolated
```

---

# 12. Parametrization

Instead of writing four tests:

```python
import pytest

@pytest.mark.parametrize("gpu_count", [1, 2, 4, 8])
def test_gpu_job(gpu_count):
    result = launch_job(gpu_count)
    assert result.success
```

pytest runs the test four times.

This is powerful for combinations like:

```text
GPU type × node count × network × workload
```

Examples:

```text
H100 × 1 node × InfiniBand
H100 × 2 nodes × InfiniBand
H100 × 4 nodes × InfiniBand
A100 × 2 nodes × Ethernet
```

---

# 13. Mocking

Suppose your code calls AWS.

You do not want every unit test to create a real EC2 instance.

Real:

```text
code
 ↓
AWS API
 ↓
actual EC2
```

Mock:

```text
code
 ↓
fake AWS response
```

General rule:

```text
unit tests → mocks often useful
integration tests → fewer mocks
end-to-end → real components
```

---

# 14. Linux From Zero

Linux machine:

```text
Hardware
   ↓
Kernel
   ↓
Processes
   ↓
Applications
```

The kernel manages:

- CPU
- memory
- devices
- filesystems
- networking
- processes
- permissions

---

# 15. Processes

When you run:

```bash
python train.py
```

Linux creates a process.

Each process gets a PID.

Show processes:

```bash
ps aux
```

Find Python:

```bash
ps aux | grep python
```

Better:

```bash
pgrep -af python
```

---

# 16. top and htop

```bash
top
```

Shows:

- CPU usage
- memory usage
- load
- running processes

Alternative:

```bash
htop
```

---

# 17. Killing Processes

Graceful termination:

```bash
kill PID
```

This normally sends SIGTERM.

Force kill:

```bash
kill -9 PID
```

This sends SIGKILL.

Use SIGKILL only when necessary because the process cannot clean up.

---

# 18. Files and Disk

```bash
ls
```

Detailed:

```bash
ls -la
```

Current directory:

```bash
pwd
```

Change directory:

```bash
cd /var/log
```

Disk usage:

```bash
df -h
```

Directory size:

```bash
du -sh folder
```

---

# 19. Logs

Last lines:

```bash
tail app.log
```

Follow live:

```bash
tail -f app.log
```

Last 100 lines:

```bash
tail -n 100 app.log
```

Search:

```bash
grep ERROR app.log
```

Case insensitive:

```bash
grep -i error app.log
```

Recursive:

```bash
grep -R "timeout" .
```

---

# 20. systemd and Kernel Logs

System logs:

```bash
journalctl
```

One service:

```bash
journalctl -u docker
```

Recent service logs:

```bash
journalctl -u docker -n 100
```

Kernel logs:

```bash
dmesg
```

Very useful for hardware and driver failures.

---

# 21. Memory

```bash
free -h
```

Shows:

- total
- used
- free
- available

System RAM and GPU memory are different things.

---

# 22. Linux Networking Commands

IP addresses:

```bash
ip addr
```

Routing:

```bash
ip route
```

Connectivity:

```bash
ping 10.0.0.5
```

DNS:

```bash
nslookup example.com
```

or:

```bash
dig example.com
```

Listening ports:

```bash
ss -tulpn
```

Find process on port:

```bash
lsof -i :8080
```

HTTP request:

```bash
curl http://localhost:8080/health
```

---

# 23. SSH

Remote login:

```bash
ssh user@server
```

Copy file:

```bash
scp file.txt user@server:/tmp/
```

Clusters often involve many remote machines.

---

# 24. Environment Variables

Set:

```bash
export NCCL_DEBUG=INFO
```

Read:

```bash
echo $NCCL_DEBUG
```

Infrastructure tools often use environment variables for configuration.

---

# 25. Networking From Zero

Two machines need to exchange data:

```text
Computer A -------- Computer B
```

A network makes that possible.

---

# 26. IP Address

Think:

```text
IP = address of a machine or network interface
```

Example:

```text
10.1.2.15
```

---

# 27. Ports

One machine can run many applications.

```text
10.1.2.15:22    SSH
10.1.2.15:80    HTTP
10.1.2.15:5432  PostgreSQL
```

IP identifies the network location.

Port identifies the application endpoint.

---

# 28. Socket

Conceptually:

```text
IP + port + protocol
```

A socket is a communication endpoint.

---

# 29. TCP

TCP provides reliable, ordered delivery.

If packets disappear:

```text
TCP retransmits
```

If packets arrive out of order:

```text
TCP reorders
```

Reliability creates overhead.

---

# 30. UDP

UDP is lighter and does not provide the same built-in delivery guarantees.

Useful in systems where low overhead matters and the application handles reliability differently.

---

# 31. Latency vs Bandwidth

## Latency

How long communication takes.

Often measured in:

```text
milliseconds
microseconds
```

## Bandwidth

How much data can move per second.

Examples:

```text
100 Gbit/s
400 Gbit/s
```

You can have high bandwidth and still have high latency.

They are separate measurements.

---

# 32. NIC

NIC means Network Interface Card.

```text
CPU/GPU
   |
  PCIe
   |
  NIC
   |
network
```

The NIC connects a server to the network.

---

# 33. Ethernet

A common network technology.

Typical stack:

```text
Application
    ↓
socket
    ↓
TCP
    ↓
IP
    ↓
Linux kernel
    ↓
NIC
    ↓
Ethernet
```

AI training requires much faster and lower-latency communication than many normal applications.

---

# 34. GPU From Zero

CPU:

```text
small number of powerful general-purpose cores
```

GPU:

```text
large number of parallel compute units
```

Deep learning uses matrix operations that GPUs perform very efficiently.

---

# 35. GPU Memory

GPU has its own high-speed memory.

Common terms:

```text
VRAM
device memory
HBM
```

Models, tensors, gradients, and intermediate results live there.

Inspect GPU:

```bash
nvidia-smi
```

You may see:

- utilization
- memory usage
- temperature
- power
- processes
- driver version

This is one of the first GPU debugging commands to remember.

---

# 36. CUDA

CUDA is NVIDIA's GPU computing platform and programming ecosystem.

Simplified stack:

```text
Python/PyTorch
       ↓
CUDA
       ↓
NVIDIA driver
       ↓
GPU
```

You do not need to write CUDA kernels for this interview.

Understand where CUDA sits.

---

# 37. GPU Driver

Linux needs a driver to communicate with NVIDIA hardware.

Problems may happen when driver, CUDA, and framework versions are incompatible.

First check:

```bash
nvidia-smi
```

---

# 38. PCIe

GPU connects into the system using PCI Express.

```text
CPU
 |
PCIe
 |
GPU
```

NIC also often uses PCIe:

```text
CPU
 |
PCIe
 |
NIC
```

Examples:

```text
PCIe Gen4 x16
PCIe Gen5 x16
```

Generation and lane count affect bandwidth.

---

# 39. NVLink

Multiple GPUs in one server need fast communication.

NVLink is a high-bandwidth GPU interconnect.

```text
GPU 0 ==== NVLink ==== GPU 1
```

NVSwitch can interconnect multiple GPUs at high bandwidth.

Inspect topology:

```bash
nvidia-smi topo -m
```

This can show relationships among:

- GPUs
- NICs
- PCIe
- NVLink
- NUMA domains

---

# 40. NUMA

NUMA means Non-Uniform Memory Access.

Large machines may have multiple CPU sockets.

```text
CPU socket 0       CPU socket 1
    |                   |
 memory 0             memory 1
```

Local memory access is usually faster than accessing memory attached to another CPU socket.

Topology matters for performance.

---

# 41. Single GPU to Multi-GPU Training

A common method is data parallelism.

Each GPU gets a copy of the model but processes different training data.

```text
             Model
       /      |       \
    GPU0     GPU1     GPU2
     |        |        |
 batch A   batch B   batch C
```

Each GPU computes gradients.

The gradients then need to be synchronized.

---

# 42. Gradients

Very simplified:

Training asks:

> How should model weights change to reduce error?

Gradients represent the direction of change.

Different GPUs compute gradients from different data batches.

Those gradients need to be combined.

---

# 43. NCCL

NCCL stands for:

```text
NVIDIA Collective Communications Library
```

Pronounced roughly:

```text
Nickel
```

NCCL provides optimized communication between NVIDIA GPUs.

Mental model:

```text
PyTorch
   ↓
NCCL
   ↓
GPU communication
```

---

# 44. Ranks

Distributed participants are often identified by rank.

```text
GPU0 = rank 0
GPU1 = rank 1
GPU2 = rank 2
GPU3 = rank 3
```

---

# 45. AllReduce

One of the most important collective operations.

Suppose:

```text
GPU0 gradient = 2
GPU1 gradient = 3
GPU2 gradient = 5
GPU3 gradient = 6
```

SUM reduction:

```text
2 + 3 + 5 + 6 = 16
```

After AllReduce:

```text
GPU0 → 16
GPU1 → 16
GPU2 → 16
GPU3 → 16
```

Every participant receives the final reduced result.

This is heavily used in distributed training.

---

# 46. Other NCCL Collectives

Recognize these names:

```text
Broadcast
Reduce
AllGather
ReduceScatter
AllToAll
```

## Broadcast

One rank sends data to all others.

## AllGather

Each rank contributes data and everyone receives all contributed data.

```text
GPU0: A
GPU1: B
GPU2: C

After AllGather:

GPU0: ABC
GPU1: ABC
GPU2: ABC
```

## ReduceScatter

Reduce values and distribute different parts of the result.

Conceptually, ReduceScatter followed by AllGather can produce the equivalent of AllReduce.

---

# 47. Multi-Node Training

Inside one server, GPUs may communicate over NVLink or PCIe.

Across servers:

```text
SERVER A                         SERVER B

GPU                                GPU
 |                                  |
PCIe                               PCIe
 |                                  |
NIC ----------- network ----------- NIC
```

Now network performance directly affects training speed.

---

# 48. RDMA

RDMA means:

```text
Remote Direct Memory Access
```

Normal networking involves significant kernel and CPU participation.

Very simplified:

```text
Application
    ↓
kernel
    ↓
network stack
    ↓
NIC
```

RDMA allows data to move between machines with much less CPU and kernel involvement in the main data path.

Conceptually:

```text
Memory A
   |
  NIC
   |
NETWORK
   |
  NIC
   |
Memory B
```

Benefits:

- lower latency
- lower CPU overhead
- high throughput

---

# 49. RDMA Is Not One Specific Network

RDMA is a communication capability.

Common technologies include:

```text
InfiniBand
RoCE
```

---

# 50. InfiniBand

InfiniBand is a high-performance network architecture used heavily in HPC and AI clusters.

Designed for:

- high bandwidth
- low latency
- RDMA

Useful commands:

```bash
ibstat
```

```bash
ibv_devinfo
```

These inspect InfiniBand and RDMA devices.

---

# 51. RoCE

RoCE means:

```text
RDMA over Converged Ethernet
```

Pronounced approximately:

```text
Rocky
```

Concept:

```text
RDMA
  ↓
Ethernet
```

Difference to remember:

```text
InfiniBand = purpose-built high-performance fabric
RoCE = RDMA carried over Ethernet
```

---

# 52. Congestion and Packet Loss

RDMA workloads can be extremely sensitive to network congestion and packet loss.

Terms you may hear:

```text
PFC
ECN
DCQCN
```

You do not need deep implementation knowledge tonight.

Know that they are used to control congestion and packet loss in high-performance Ethernet/RoCE networks.

---

# 53. GPUDirect RDMA

Without GPUDirect RDMA, communication may require extra staging through system memory.

Simplified:

```text
GPU
 ↓
system memory
 ↓
CPU/network path
 ↓
NIC
```

With GPUDirect RDMA, supported NICs can transfer data much more directly to and from GPU memory.

```text
GPU memory
    |
   PCIe
    |
   NIC
    |
 NETWORK
    |
   NIC
    |
   PCIe
    |
GPU memory
```

Interview-ready sentence:

> GPUDirect RDMA reduces unnecessary CPU involvement and memory copies when transferring data between GPUs across machines.

---

# 54. PyTorch Distributed

Distributed training often launches multiple processes.

```text
process 0 → GPU0
process 1 → GPU1
process 2 → GPU2
process 3 → GPU3
```

For NVIDIA GPUs, NCCL is commonly used as the communication backend.

```text
PyTorch Distributed
        ↓
       NCCL
        ↓
NVLink / PCIe / RDMA / network
        ↓
       GPUs
```

---

# 55. Why Distributed Training Hangs

Suppose eight ranks enter AllReduce.

```text
rank 0 → AllReduce
rank 1 → AllReduce
rank 2 → AllReduce
...
rank 7 → crashed
```

Others may wait forever or until timeout.

Possible causes:

- one GPU crashed
- one process died
- network failure
- wrong collective order
- NCCL configuration problem
- driver problem
- timeout

---

# 56. NCCL Debugging

Useful environment variable:

```bash
export NCCL_DEBUG=INFO
```

Then run workload.

Logs may reveal:

- ranks
- interfaces
- connections
- transport selection
- errors

This is one of the most useful NCCL troubleshooting settings to remember.

---

# 57. nccl-tests

NVIDIA provides an open-source test repository called `nccl-tests`.

Common programs include:

```text
all_reduce_perf
all_gather_perf
reduce_scatter_perf
```

Typical SDET workflow:

```text
run NCCL benchmark
↓
record latency and bandwidth
↓
compare with baseline
↓
detect performance regression
```

---

# 58. GB/s vs Gb/s

Capitalization matters.

```text
B = bytes
b = bits
```

8 bits = 1 byte.

Example:

```text
400 Gbit/s ÷ 8 = 50 GB/s
```

Before protocol overhead and other losses.

---

# 59. GPU Performance Debugging

Suppose training becomes 30% slower.

Do not immediately blame the GPU.

Think layer by layer:

```text
Application
    ↓
PyTorch
    ↓
NCCL
    ↓
GPU compute
    ↓
GPU interconnect
    ↓
PCIe
    ↓
NIC
    ↓
Network
```

Start by reproducing and collecting a baseline.

Check GPU:

```bash
nvidia-smi
```

Ask:

```text
Are GPUs utilized?
Is temperature normal?
Is power normal?
Is memory full?
Is any GPU missing?
```

Check topology:

```bash
nvidia-smi topo -m
```

Enable NCCL logs:

```bash
export NCCL_DEBUG=INFO
```

Run isolated communication tests using `nccl-tests`.

Check network:

- link status
- errors
- packet drops
- RDMA state
- bandwidth

Check system:

- CPU
- RAM
- disk
- kernel logs

Then compare:

```text
healthy node vs unhealthy node
```

This comparative debugging technique is powerful.

---

# 60. DCGM

DCGM means:

```text
Data Center GPU Manager
```

Think:

```text
nvidia-smi = direct GPU inspection
DCGM = fleet-level GPU monitoring, health, and diagnostics
```

DCGM can help with:

- GPU health
- temperature
- power
- memory errors
- PCIe
- NVLink
- utilization
- diagnostics

---

# 61. Passive Monitoring vs Active Diagnostics

Passive monitoring:

```text
observe GPU while workload runs
```

Active diagnostics:

```text
intentionally stress or test hardware
```

Example:

```text
Passive:
Has PCIe shown errors recently?

Active:
Stress PCIe and test whether it passes.
```

This distinction is useful in SDET conversations.

---

# 62. Docker From Zero

Applications need dependencies.

Example:

```text
Python
PyTorch
NCCL libraries
system packages
configuration
```

A container packages the environment so it behaves consistently across machines.

Mental model:

```text
IMAGE = packaged blueprint
CONTAINER = running instance of image
```

---

# 63. Dockerfile

Example:

```dockerfile
FROM python:3.12

WORKDIR /app

COPY requirements.txt .

RUN pip install -r requirements.txt

COPY . .

CMD ["python", "app.py"]
```

Meaning:

```text
FROM = base image
WORKDIR = working directory
COPY = copy files
RUN = command executed during build
CMD = default command at container startup
```

---

# 64. Docker Commands

Build image:

```bash
docker build -t myapp .
```

Run:

```bash
docker run myapp
```

List running containers:

```bash
docker ps
```

Logs:

```bash
docker logs CONTAINER_ID
```

Shell inside container:

```bash
docker exec -it CONTAINER_ID bash
```

Stop:

```bash
docker stop CONTAINER_ID
```

---

# 65. Containers vs Virtual Machines

VM:

```text
application
guest operating system
hypervisor
host
```

Container:

```text
application
container isolation
host Linux kernel
```

Containers share the host kernel while keeping processes isolated.

---

# 66. Namespaces and cgroups

## Namespace

Controls what a process can see.

Examples:

- processes
- networking
- filesystem view

## cgroups

Controls how many resources a process or container can use.

Examples:

- CPU
- memory

Mnemonic:

```text
namespace = what you can see
cgroup = how much you can use
```

---

# 67. Kubernetes From Zero

Docker can run containers.

Kubernetes coordinates containers across many machines.

It handles:

- scheduling
- deployment
- restart
- networking
- scaling
- configuration

---

# 68. Kubernetes Cluster

```text
Kubernetes cluster

Control Plane
       |
 +-----+-----+
 |           |
Node 1      Node 2
```

Nodes are machines that run workloads.

---

# 69. Pod

A pod is the basic Kubernetes workload unit.

Usually:

```text
Pod
 |
Container
```

Pods receive lifecycle and networking management from Kubernetes.

---

# 70. Deployment

Suppose you want three copies of an API.

```yaml
replicas: 3
```

If one dies:

```text
desired = 3
actual = 2
```

Kubernetes creates another.

---

# 71. Desired State

You tell Kubernetes what you want.

```text
I want 3 replicas.
```

Kubernetes continuously tries to make the actual state match the desired state.

This is declarative system design.

---

# 72. Service

Pods can be replaced and their IPs can change.

A Service provides a stable network abstraction.

```text
Client
  |
Service
 / | \
P1 P2 P3
```

---

# 73. ConfigMap and Secret

## ConfigMap

Non-sensitive configuration.

```text
LOG_LEVEL=INFO
```

## Secret

Sensitive values.

Examples:

- passwords
- tokens
- API keys

---

# 74. Resource Requests and Limits

A pod can request:

```text
2 CPU
4 GB RAM
1 GPU
```

GPU resources may appear as:

```yaml
nvidia.com/gpu: 1
```

The scheduler uses requests when deciding where to place workloads.

---

# 75. Kubernetes Probes

## Liveness probe

Question:

> Is this application alive?

If it repeatedly fails, Kubernetes may restart the container.

## Readiness probe

Question:

> Is this application ready to receive traffic?

If not, traffic should not be sent to the pod.

## Startup probe

Question:

> Has the application finished starting?

Useful for slow-starting applications.

---

# 76. kubectl Commands

Pods:

```bash
kubectl get pods
```

Details:

```bash
kubectl describe pod POD_NAME
```

Logs:

```bash
kubectl logs POD_NAME
```

Follow logs:

```bash
kubectl logs -f POD_NAME
```

Shell:

```bash
kubectl exec -it POD_NAME -- bash
```

Nodes:

```bash
kubectl get nodes
```

Deployments:

```bash
kubectl get deployments
```

Services:

```bash
kubectl get services
```

All common resources:

```bash
kubectl get all
```

---

# 77. CrashLoopBackOff

Means:

```text
container starts
↓
crashes
↓
Kubernetes restarts it
↓
crashes again
↓
restart backoff grows
```

Debug:

```bash
kubectl describe pod POD
```

Then:

```bash
kubectl logs POD
```

Previous crashed instance:

```bash
kubectl logs POD --previous
```

Very useful command.

---

# 78. Pending Pod

Pod exists but has not been scheduled or started.

Possible causes:

- insufficient CPU
- insufficient memory
- no GPU available
- node selector mismatch
- taints
- volume issue
- scheduler problem

Use:

```bash
kubectl describe pod POD
```

Look at the Events section.

---

# 79. Helm

Kubernetes manifests can become large and repetitive.

Helm packages Kubernetes resources into a chart.

Think:

```text
Helm = package manager + templating for Kubernetes
```

Important concepts:

```text
chart
values.yaml
templates
helm install
helm upgrade
helm rollback
```

You do not need advanced Helm templating tonight.

---

# 80. Slurm

Slurm is a workload manager and scheduler used heavily in HPC and AI clusters.

Concepts:

```text
node = machine
job = work to execute
partition = group or queue of nodes
scheduler = decides when and where job runs
```

Commands:

Run work:

```bash
srun
```

Submit batch job:

```bash
sbatch train.sh
```

View queue:

```bash
squeue
```

Cluster info:

```bash
sinfo
```

Cancel:

```bash
scancel JOB_ID
```

Mental comparison:

```text
Kubernetes → schedules pods and containers
Slurm → schedules HPC jobs and resources
```

---

# 81. Distributed Systems From Zero

A distributed system is multiple machines working together.

```text
Machine A
Machine B
Machine C
```

They communicate over a network.

Main complication:

```text
machines can fail independently
networks can fail
```

---

# 82. Partial Failure

Example:

```text
Node A healthy
Node B healthy
Node C dead
Node D healthy
```

The system is not simply fully up or fully down.

Part of it failed.

That is partial failure.

---

# 83. Timeout

If Node A calls Node B, A should not wait forever.

```text
wait 5 seconds
then treat as failed
```

This is a timeout.

---

# 84. Retry

A failed request may be tried again.

But careless retries can cause:

- duplicate operations
- extra load
- retry storms

---

# 85. Idempotency

An idempotent operation can be repeated without changing the intended result beyond the first successful execution.

Example:

```text
SET status = ready
```

Repeated twice still ends at ready.

But:

```text
TRANSFER $100
```

Repeated twice could transfer $200.

Retries work much better when operations are idempotent.

---

# 86. Exponential Backoff

Instead of retrying constantly:

```text
retry immediately
retry immediately
retry immediately
```

Use:

```text
1 sec
2 sec
4 sec
8 sec
```

Often add jitter so many machines do not retry simultaneously.

---

# 87. Race Condition

Outcome depends on timing.

Example:

```text
Thread A reads counter = 5
Thread B reads counter = 5

A writes 6
B writes 6
```

Expected:

```text
7
```

Actual:

```text
6
```

This is a race condition.

---

# 88. Deadlock

A waits for B.

B waits for A.

```text
A waits for lock B
B waits for lock A
```

Neither can continue.

---

# 89. Straggler

One worker is much slower than others.

```text
GPU0 done
GPU1 done
GPU2 done
GPU3 still running
```

Collective operations may wait for GPU3.

One slow participant can reduce overall distributed training performance.

---

# 90. CI/CD From Zero

CI means Continuous Integration.

Typical pipeline:

```text
checkout
↓
build
↓
test
↓
report
```

CD may mean Continuous Delivery or Continuous Deployment depending on context.

---

# 91. Example Infrastructure Pipeline

```text
git push
   ↓
lint
   ↓
unit tests
   ↓
build Docker image
   ↓
integration tests
   ↓
deploy test cluster
   ↓
GPU tests
   ↓
performance tests
   ↓
publish artifact
```

---

# 92. Artifact

A build artifact is an output produced by the pipeline.

Examples:

- Docker image
- binary
- package
- test report
- logs

---

# 93. Quality Gates

A test stage can prevent bad code from moving forward.

Example:

```text
Unit tests PASS
Integration PASS
GPU smoke PASS
NCCL benchmark PASS
Performance regression within threshold

→ release allowed
```

---

# 94. Parallel Tests

Instead of:

```text
A then B then C then D
```

run:

```text
A B C D simultaneously
```

Faster, but introduces problems like:

- shared state
- same ports
- same GPU
- same database
- same cluster names
- resource collisions

An SDET framework should prevent those conflicts.

---

# 95. Terraform

Terraform provides Infrastructure as Code.

Instead of manually creating cloud infrastructure, describe it in configuration.

Example conceptually:

```hcl
resource "aws_instance" "worker" {
    ...
}
```

Commands:

```bash
terraform plan
```

Shows proposed changes.

```bash
terraform apply
```

Applies them.

```bash
terraform destroy
```

Removes infrastructure.

Advantages:

- repeatable
- version controlled
- automatable
- reviewable

---

# 96. Python You Must Know

## List

```python
gpus = ["gpu0", "gpu1", "gpu2"]
```

Ordered collection.

## Dictionary

```python
gpu = {
    "id": 0,
    "memory": 80,
    "healthy": True
}
```

Key-value mapping.

## Set

```python
nodes = {"node1", "node2"}
```

Unique values.

## Tuple

```python
location = ("node1", 0)
```

Fixed grouping.

---

# 97. Python Exceptions

```python
try:
    connect()
except ConnectionError:
    print("connection failed")
```

Cleanup:

```python
try:
    run_test()
finally:
    cleanup()
```

This is very relevant to test infrastructure.

---

# 98. Context Managers

Example:

```python
with open("log.txt") as file:
    data = file.read()
```

The resource is automatically closed.

Context managers are useful for resources like:

- files
- SSH sessions
- temporary directories
- database transactions
- cluster lifecycle wrappers

---

# 99. Generators

Normal function returns once.

Generator uses:

```python
yield
```

It produces values incrementally.

pytest fixtures also use `yield` for setup and cleanup.

---

# 100. Decorators

Examples:

```python
@pytest.fixture
```

and:

```python
@pytest.mark.parametrize(...)
```

Decorators attach or modify behavior of a function.

You do not need deep metaprogramming knowledge tonight.

---

# 101. subprocess

Very useful in infrastructure tests.

```python
import subprocess

result = subprocess.run(
    ["nvidia-smi"],
    capture_output=True,
    text=True
)

print(result.stdout)
```

Mental model:

```text
Python
  ↓
run Linux command
  ↓
capture result
  ↓
parse output
  ↓
assert expected behavior
```

---

# 102. Threads vs Processes

Thread:

```text
shares process memory
```

Process:

```text
separate memory space
```

Rule of thumb in Python:

```text
I/O-bound → threads or async often useful
CPU-bound → multiprocessing often useful
```

Infrastructure automation is often I/O-heavy because it spends time on:

- network calls
- SSH
- APIs
- disk

---

# 103. async

Sequential:

```text
connect node1
wait
connect node2
wait
connect node3
wait
```

Async can overlap waiting time across many connections.

This can dramatically speed up cluster automation.

Know the concept more than syntax for tomorrow.

---

# 104. Go From Zero

Do not try to become a Go expert tonight.

Function:

```go
func add(a int, b int) int {
    return a + b
}
```

Variable:

```go
name := "node1"
```

Struct:

```go
type Node struct {
    Name string
    GPUCount int
}
```

Method:

```go
func (n Node) Healthy() bool {
    return true
}
```

---

# 105. Go Error Handling

```go
result, err := doSomething()

if err != nil {
    return err
}
```

Go commonly returns errors explicitly instead of using exceptions like Python.

---

# 106. Goroutines

Lightweight concurrent execution.

```go
go runTask()
```

Runs the function concurrently.

---

# 107. Channels

Goroutines communicate using channels.

```text
goroutine A
     |
   channel
     |
goroutine B
```

---

# 108. context.Context

You may see:

```go
ctx context.Context
```

Common uses:

- cancellation
- timeouts
- deadlines
- request-scoped information

Very common in infrastructure services.

---

# 109. SQL Basics

Assume table:

```text
jobs

id | node | status | duration
```

Select:

```sql
SELECT *
FROM jobs;
```

Filter:

```sql
SELECT *
FROM jobs
WHERE status = 'FAILED';
```

Count:

```sql
SELECT COUNT(*)
FROM jobs;
```

Group:

```sql
SELECT node, COUNT(*)
FROM jobs
GROUP BY node;
```

Sort:

```sql
SELECT *
FROM jobs
ORDER BY duration DESC;
```

Limit:

```sql
SELECT *
FROM jobs
ORDER BY duration DESC
LIMIT 10;
```

---

# 110. SQL Join

```sql
SELECT jobs.id, nodes.hostname
FROM jobs
JOIN nodes
ON jobs.node_id = nodes.id;
```

JOIN combines related rows from multiple tables.

---

# 111. SQL Aggregation

```sql
SELECT node_id, AVG(duration)
FROM jobs
GROUP BY node_id;
```

---

# 112. WHERE vs HAVING

```text
WHERE = filters rows before grouping
HAVING = filters grouped results
```

Example:

```sql
SELECT node_id, COUNT(*)
FROM jobs
GROUP BY node_id
HAVING COUNT(*) > 10;
```

---

# 113. Observability

Three major concepts:

```text
metrics
logs
traces
```

## Metrics

Examples:

```text
GPU utilization = 94%
temperature = 76 C
network throughput = ...
```

## Logs

Example:

```text
NCCL connection failed
```

## Traces

Follow a request across multiple services.

For GPU infrastructure, metrics and logs are especially important.

---

# 114. Prometheus

Prometheus collects time-series metrics.

Example:

```text
gpu_utilization{node="node4",gpu="0"} 92
```

---

# 115. Grafana

Grafana visualizes metrics.

```text
Prometheus → Grafana dashboard
```

Useful charts:

- GPU usage
- temperature
- GPU memory
- network throughput
- job duration
- failure rate

---

# 116. DCGM Exporter

Typical monitoring path:

```text
GPU
 ↓
DCGM
 ↓
DCGM Exporter
 ↓
Prometheus
 ↓
Grafana
```

This is common GPU observability architecture.

---

# 117. How Everything Becomes One SDET System

A real infrastructure test pipeline may look like:

```text
GitHub commit
      ↓
CI pipeline
      ↓
build Docker image
      ↓
Terraform provisions test environment
      ↓
Kubernetes/Slurm deploy workloads
      ↓
pytest orchestrates tests
      ↓
PyTorch distributed job runs
      ↓
NCCL communicates between GPUs
      ↓
RDMA network transfers data
      ↓
DCGM records GPU health
      ↓
Prometheus collects metrics
      ↓
test compares against expected thresholds
      ↓
logs/artifacts uploaded
      ↓
cluster destroyed
```

This is the core mental model for the role.

---

# 118. Example Sophisticated GPU Test

Requirement:

> 16 GPUs across two servers should complete NCCL AllReduce without errors and meet a minimum bandwidth threshold.

Possible test flow:

```text
1. Verify both nodes are reachable.

2. Verify 8 GPUs are visible on each node.
   nvidia-smi

3. Verify GPU health.
   DCGM

4. Verify network interfaces.

5. Verify RDMA devices.

6. Run NCCL all_reduce_perf across all 16 GPUs.

7. Capture:
   bandwidth
   latency
   NCCL logs
   GPU metrics
   network errors

8. Assert:
   process exit code == 0
   bandwidth > threshold
   no GPU health failures
   no network failures

9. Store logs and artifacts.

10. Clean up the environment.
```

This is infrastructure SDET thinking.

---

# 119. Debugging a 40% Bandwidth Drop

Do not guess.

Reduce the problem.

```text
Was code changed?
       |
      yes/no
       ↓
single GPU compute healthy?
       ↓
single-node NCCL healthy?
       ↓
multi-node NCCL bad?
       ↓
likely inter-node path
       ↓
NIC / RDMA / network / topology
```

Example:

```text
single GPU benchmark: PASS
8 GPUs same server: PASS
16 GPUs across two servers: FAIL
```

Inference:

The problem is less likely to be raw GPU compute.

The new layer introduced is cross-host communication:

- NIC
- network
- RDMA
- topology
- cross-host configuration

This is strong debugging reasoning.

---

# 120. Debugging a Pending Kubernetes GPU Pod

Check:

```bash
kubectl get pods
```

If status is:

```text
Pending
```

Then:

```bash
kubectl describe pod POD
```

Events might say:

```text
Insufficient nvidia.com/gpu
```

Possible causes:

- all GPUs already allocated
- NVIDIA device plugin problem
- node unavailable
- resource request wrong

---

# 121. Debugging CrashLoopBackOff

Check:

```bash
kubectl logs POD --previous
```

Example failure:

```text
CUDA driver version insufficient
```

Then investigate driver/runtime compatibility.

---

# 122. Debugging One Bad GPU

Check:

```bash
nvidia-smi
```

Then:

```text
DCGM health
DCGM diagnostics
dmesg
```

Compare bad GPU with healthy GPUs.

Look for:

- XID errors
- memory errors
- thermal issues
- PCIe errors
- NVLink errors

---

# 123. What Not to Spend Time On Tonight

Do not spend hours learning:

- CUDA kernel programming
- RDMA verbs API implementation
- BGP internals
- Kubernetes operator development
- advanced Go generics
- InfiniBand subnet manager internals
- CUDA memory coalescing optimization
- NCCL source code internals
- advanced Slurm administration

For an initial hiring-manager screen, these are low priority.

---

# 124. Exact Study Order for Today

| Priority | Topic | Target |
|---|---|---:|
| Critical | SDET/testing + pytest | 1.5 h |
| Critical | Linux debugging | 1 h |
| Critical | Networking fundamentals | 1 h |
| Critical | GPU → PCIe → NVLink → NCCL | 1.5 h |
| Critical | RDMA/RoCE/InfiniBand | 1 h |
| Critical | Docker/Kubernetes | 1.5 h |
| High | Distributed systems | 45 min |
| High | CI/CD | 30 min |
| High | DCGM/observability | 30 min |
| High | Slurm | 30 min |
| Medium | Go reading | 30 min |
| Medium | SQL | 30 min |
| Final | Resume stories | 1 h |

---

# 125. Final Mental Model

You should be able to mentally walk through:

```text
pytest
  ↓
CI
  ↓
Kubernetes / Slurm
  ↓
Linux node
  ↓
Docker container
  ↓
PyTorch
  ↓
NCCL
  ↓
GPU
  ↓
PCIe / NVLink
  ↓
NIC
  ↓
RDMA
  ↓
RoCE / InfiniBand
  ↓
remote node
```

For every layer, ask four questions:

```text
What is it?
Why is it there?
How can it fail?
How do I inspect or test it?
```

If you can answer those four questions for each layer, you will have the right mental model for the interview.

---

# 126. Commands Worth Memorizing

## Linux

```bash
ps aux
pgrep -af python
top
free -h
df -h
dmesg
journalctl
ip addr
ip route
ping HOST
ss -tulpn
lsof -i :PORT
curl URL
ssh user@host
```

## GPU

```bash
nvidia-smi
nvidia-smi topo -m
```

## NCCL

```bash
export NCCL_DEBUG=INFO
```

## RDMA / InfiniBand

```bash
ibstat
ibv_devinfo
```

## Docker

```bash
docker build -t myapp .
docker run myapp
docker ps
docker logs CONTAINER_ID
docker exec -it CONTAINER_ID bash
```

## Kubernetes

```bash
kubectl get pods
kubectl describe pod POD
kubectl logs POD
kubectl logs POD --previous
kubectl exec -it POD -- bash
kubectl get nodes
kubectl get deployments
kubectl get services
kubectl get all
```

## Slurm

```bash
srun
sbatch train.sh
squeue
sinfo
scancel JOB_ID
```

## Terraform

```bash
terraform plan
terraform apply
terraform destroy
```

---

# 127. High-Value Interview Phrases

These are useful ways to explain your reasoning naturally.

### When debugging

> I would first reproduce the issue and establish whether it is functional, performance-related, or environment-specific. Then I would isolate the layer by comparing a healthy and unhealthy setup and reducing the problem from application to system, GPU, and network layers.

### When discussing flaky tests

> I would not treat retries as the real fix. I would capture enough state to understand the source of nondeterminism, then improve isolation and reproducibility.

### When discussing distributed failures

> In a distributed system I assume partial failure is possible, so I care about timeouts, retries, idempotency, and observability.

### When discussing GPU performance

> I would separate compute performance from communication performance. If single-GPU and single-node tests are healthy but multi-node performance regresses, I would focus on the NIC, RDMA path, network fabric, NCCL transport, and topology.

### When discussing test framework design

> I would keep hardware setup and teardown in reusable fixtures, parameterize the important cluster configurations, capture logs and metrics as artifacts, and keep unit, integration, and end-to-end coverage separate so failures are easier to localize.

---

# 128. Resources

Useful authoritative documentation:

- pytest parametrization: https://docs.pytest.org/en/stable/how-to/parametrize.html
- Docker getting started: https://docs.docker.com/get-started/
- Kubernetes probes: https://kubernetes.io/docs/concepts/workloads/pods/probes/
- NVIDIA NCCL collective operations: https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/usage/collectives.html
- NVIDIA DCGM: https://docs.nvidia.com/datacenter/dcgm/latest/

Useful Kubernetes beginner video:

- Kubernetes Course - Full Beginners Tutorial: https://www.youtube.com/watch?v=d6WC5n9G_sM

Useful sections from that video:

```text
00:02:40  What is Kubernetes
00:06:46  What is a Pod
00:08:22  Cluster and Nodes
00:10:40  Services
00:14:17  kubectl
00:40:36  Create Pod
00:55:17  Deployment
01:09:23  Service
01:40:26  Deployment using Docker image
01:45:49  Scaling
01:56:49  Rolling updates
02:05:30  Pod deletion/recovery
02:10:49  YAML
```

---

# End

Focus on understanding the architecture and debugging flow rather than memorizing isolated definitions.
