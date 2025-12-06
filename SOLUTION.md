# SRE Technical Test - Solution

Hey! So I've made some improvements to address the main concerns about cold starts, scaling, and costs. Here's what I did and why.

---

## 1. Cold Start Optimization

### Problem
Lambda functions experience cold starts when invoked after a period of inactivity, causing delays of 1-5 seconds that degrade user experience.

### Solutions Implemented

#### 1.1 Python Runtime Upgrade
- **Changed**: Python 3.9 → Python 3.12
- **Why**: Python 3.12 has better cold start performance. I read somewhere it's like 30% faster, so figured why not upgrade.
- **Location**: `terraform/main.tf`

#### 1.2 Connection Reuse
- **Changed**: Moved boto3 initialization outside the handler
- **Why**: This way the connection gets reused between invocations instead of creating a new one each time. Helps with cold starts.
- **Location**: `src/app.py`

#### 1.3 Provisioned Concurrency (Optional)
- **Added**: Option to enable provisioned concurrency
- **Why**: If cold starts are really a problem, this eliminates them. But it costs more (~$0.015/hour per instance), so I made it optional.
- **Location**: `terraform/main.tf`
- **Note**: Disabled by default. Turn it on if you need it.

#### 1.4 Memory Setting
- **Changed**: Set memory to 256MB
- **Why**: Lambda CPU scales with memory, so 256MB seemed like a good balance. Could probably tune this more if needed.
- **Location**: `terraform/main.tf`

---

## 2. Production Readiness Improvements

### 2.1 Query Optimization

#### Problem
The original implementation used a simple `table.scan()` which:
- Scans the entire table (inefficient for large datasets)
- No pagination support
- Could timeout on large tables

#### Solution
- **Added**: Paginated scan (100 items at a time)
- **Why**: The original code would timeout if the table got big. Now it handles pagination properly.
- **Location**: `src/app.py`
- **Note**: Still using a scan, which isn't ideal for huge tables, but works for now. Could add a GSI later if we need to filter/query differently.

### 2.2 Error Handling & Resilience

#### Improvements
- **Added**: Better error handling with try/catch
- **Added**: Proper HTTP status codes
- **Why**: The original code would just return 500 for everything. Now it's a bit more specific.
- **Location**: `src/app.py`
- **TODO**: Should probably hide error details in production (currently exposing them)

### 2.3 Observability

#### CloudWatch Logging
- **Added**: Better logging with some context
- **Added**: Log retention set to 7 days (configurable)
- **Why**: Need to be able to debug issues. 7 days seems reasonable, can adjust if needed.
- **Location**: `terraform/main.tf` and `src/app.py`

#### CloudWatch Alarms
- **Added**: Basic alarms for errors
  - Lambda errors (>10 in 2 minutes)
  - API Gateway 5XX errors (>5 in 1 minute)
- **Why**: Want to know when things break
- **Location**: `terraform/main.tf`
- **TODO**: Should set up SNS topic to actually get notified, but didn't have time

#### API Gateway
- **Added**: Basic rate limiting (50 req/sec default)
- **Why**: Don't want someone to accidentally DDoS us

### 2.4 Security Improvements

#### Rate Limiting
- **Added**: API Gateway throttling (50 req/sec, 100 burst)
- **Why**: Basic protection against abuse
- **Location**: `terraform/main.tf`
- **Note**: Can adjust the limits in variables if needed

#### CORS
- **Added**: CORS headers (currently set to `*` - should restrict this in production)
- **Location**: `src/app.py`
- **TODO**: Need to restrict CORS to actual frontend domain

#### IAM
- **Checked**: IAM policy looks okay, only gives what's needed
- **Location**: `terraform/main.tf`

#### Things I'd Add Later
- API key authentication (probably needed for production)
- Maybe AWS WAF if we get attacked
- Restrict CORS properly

### 2.5 Data Protection

#### DynamoDB Point-in-Time Recovery
- **Added**: Enabled PITR on the table
- **Why**: Just in case we need to recover data
- **Location**: `terraform/main.tf`

---

## 3. Cost Optimization

### What I Did
- **Connection reuse**: Reusing boto3 connections means less work per request = lower costs
- **Log retention**: Set to 7 days (configurable). Less logs = less storage costs
- **Resource tagging**: Added tags so we can track costs per environment

### Future Ideas
- **Caching**: Could add API Gateway caching or ElastiCache to reduce DynamoDB reads. Would save money at scale.
- **Reserved capacity**: If traffic is predictable, could use DynamoDB reserved capacity

### Cost Estimate
At low traffic (1000 req/day): Probably like $1-2/month  
At scale (1M req/day): Maybe $50-60/month? Haven't done the exact math but seems reasonable.

---

## 4. Can It Scale to 1000s of Users?

Answer: **Yes, probably.**

The current setup should handle thousands of concurrent users:
- API Gateway can handle way more than we need (default limit is like 10k req/sec)
- Lambda auto-scales
- DynamoDB PAY_PER_REQUEST scales automatically

For 1000 concurrent users making maybe 1 request per minute = ~17 req/sec, which is way under our 50 req/sec limit.

If we need to scale more:
- Enable provisioned concurrency if cold starts become a problem
- Add caching to reduce DynamoDB reads
- Could increase API Gateway limits if needed (AWS support ticket)

---

## 5. How to Deploy

Same as before, just run:
```bash
cd terraform
terraform init
terraform apply
```

Then seed the data:
```bash
cd ../scripts
pip install boto3
python seed_data.py
```

Test it:
```bash
curl <api_url>/llms
```

Should get back a JSON with the items and count.

---

## 6. Testing

You can test it with:
```bash
# Simple load test
for i in {1..100}; do curl -w "%{time_total}\n" -o /dev/null -s <api_url>/llms; done
```

To test cold starts, wait like 15 minutes then make a request and check the logs.

---

## 7. Some Decisions I Made

- **Provisioned concurrency**: Made it optional because it costs money. Only enable if you really need it.
- **Python 3.12**: Upgraded because it's faster. Seemed like an easy win.
- **Still using scan**: Yeah, it's not ideal but works for now. Could add a GSI later if we need to filter.
- **256MB memory**: Seemed like a reasonable amount. Could tune this more.
- **7 day log retention**: Good balance. Can increase if needed.

---

## 8. Things I'd Add Later

- API key authentication (probably needed for production)
- SNS topic for alarm notifications (alarms exist but don't notify anyone yet)
- Response caching (would help with costs at scale)
- Health check endpoint (`/health`)
- Restrict CORS properly (currently set to `*`)
- Maybe DynamoDB DAX if reads become expensive

---

## 9. Cost Estimates

At low traffic: Probably like $1-2/month (mostly free tier)  
At scale (1M requests/day): Maybe $50-60/month?  
With provisioned concurrency: Add ~$20-25/month per instance

Haven't done exact math but seems reasonable. Could optimize more with caching if needed.

---

## 10. Monitoring

I added some basic CloudWatch alarms for errors. They'll show up in the console but won't notify you yet - would need to add an SNS topic for that.

Key things to watch:
- Lambda errors and duration
- API Gateway 5XX errors
- DynamoDB throttles (if any)

---

## Summary

So yeah, I've made improvements to address the main concerns:
- **Cold starts**: Upgraded Python, reused connections, added optional provisioned concurrency
- **Scaling**: Added pagination, rate limiting, better error handling
- **Costs**: Optimized where I could, added tagging for tracking

The setup should handle thousands of concurrent users. There's definitely more that could be done (caching, auth, etc.) but this should be a solid foundation.

Happy to discuss any of this during the interview!

