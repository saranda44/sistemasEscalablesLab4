# Lab 4 — ALB + Lambda + ElastiCache + RDS

Deploys, on an AWS Academy Learner Lab account:

- An **ALB** with two POST routes, `/cached` and `/nocache`.
- **One Lambda function** (Python 3.12) that backs both routes — it reads the
  request path and branches internally: `/cached` does cache-aside (lazy
  loading) reads through **ElastiCache Redis**; `/nocache` always reads
  straight from **RDS PostgreSQL**.
- RDS PostgreSQL (`db.t3.micro`) and ElastiCache Redis (`cache.t3.micro`),
  both private, reachable only from the Lambda's security group.
- `sql/seed.sql` — an ~200-row product catalog, bundled into the
  Lambda package and run once against RDS right after deploy so there's real data to query.

State is stored remotely in the pre-existing S3 bucket `sara.aranda`
(`backend.tf`), using the `academy` AWS CLI profile and Terraform's native S3
state locking.


## Deploy

```bash
terraform init
terraform plan
terraform apply
```

`terraform apply` builds the Lambda zip, creates the AWS
resources, and invokes the function once to seed RDS from `sql/seed.sql`.

Outputs include `alb_dns_name`, `cached_endpoint`, `nocache_endpoint`.

## Try it

```bash
ALB=$(terraform output -raw alb_dns_name)

curl -s -X POST "http://$ALB/cached"  -d '{"id": 7}'   # first hit: source=database
curl -s -X POST "http://$ALB/cached"  -d '{"id": 7}'   # second hit: source=cache
curl -s -X POST "http://$ALB/nocache" -d '{"id": 7}'   # always source=database
```

## Load test with wrk2

wrk2 (https://github.com/giltene/wrk2) is not a package-manager install — build it:

```bash
git clone https://github.com/giltene/wrk2 ~/wrk2
cd ~/wrk2 && make
```

Then, with a constant target throughput (`-R`) so latency reflects real
queueing rather than best-effort throughput:

```bash
ALB=$(terraform output -raw alb_dns_name)

# baseline: hits RDS on every request
~/wrk2/wrk -t4 -c50 -d30s -R500 --latency \
  -s benchmark/nocache.lua "http://$ALB/nocache"

# cache-aside: most requests are served from Redis after warm-up
~/wrk2/wrk -t4 -c50 -d30s -R500 --latency \
  -s benchmark/cached.lua "http://$ALB/cached"
```

## Cleanup

```bash
terraform destroy
```

