# Fix Local S3 Uploads — Reference Guide

Browser-based file uploads fail in local dev because LocalStack S3 differs from real AWS in three ways. This guide fixes all three. Each fix is independent — apply only what's missing.

## Quick Detection

Run these 4 checks against `boards-cloud-service/`. Each returns APPLIED or MISSING.

| # | Check | File (relative to `src/`) | Grep Pattern | What It Fixes |
|---|-------|---------------------------|-------------|---------------|
| 1 | PresignedUrlProtocol property | `Infrastructure/Infrastructure.S3/S3Storage.cs` | `PresignedUrlProtocol` | Presigned URLs use HTTPS but LocalStack only serves HTTP |
| 2 | ForcePathStyle on S3 client | `Infrastructure/Infrastructure.Local.Core/Infrastructure/LocalStack/LocalStackExtensions.cs` | `ForcePathStyle` | Virtual-host URLs (`bucket.localhost:4566`) don't resolve locally |
| 3 | CORS on S3 buckets | `Infrastructure/Infrastructure.Local/Extensions/S3LifecycleHooksExtensions.cs` | `PutCORSConfigurationAsync` | Browser blocks cross-origin PUT from `localhost:4200` to LocalStack |
| 4 | S3Storage DI with HTTP protocol | `Infrastructure/Infrastructure.Local/Infrastructure/LocalStack/LocalStackSetupInitializationHook.cs` | `PresignedUrlProtocol = Protocol.HTTP` | Wires fix #1 into local dev DI container |

**Detection script (run from repo root):**

```bash
SRC="src"
echo "=== S3 Local Upload Fix Detection ==="

grep -q "PresignedUrlProtocol" "$SRC/Infrastructure/Infrastructure.S3/S3Storage.cs" 2>/dev/null \
  && echo "[1] PresignedUrlProtocol property: APPLIED" \
  || echo "[1] PresignedUrlProtocol property: MISSING"

grep -q "ForcePathStyle" "$SRC/Infrastructure/Infrastructure.Local.Core/Infrastructure/LocalStack/LocalStackExtensions.cs" 2>/dev/null \
  && echo "[2] ForcePathStyle on S3 client:   APPLIED" \
  || echo "[2] ForcePathStyle on S3 client:   MISSING"

grep -q "PutCORSConfigurationAsync" "$SRC/Infrastructure/Infrastructure.Local/Extensions/S3LifecycleHooksExtensions.cs" 2>/dev/null \
  && echo "[3] CORS on S3 buckets:            APPLIED" \
  || echo "[3] CORS on S3 buckets:            MISSING"

grep -q "PresignedUrlProtocol = Protocol.HTTP" "$SRC/Infrastructure/Infrastructure.Local/Infrastructure/LocalStack/LocalStackSetupInitializationHook.cs" 2>/dev/null \
  && echo "[4] S3Storage DI with HTTP:        APPLIED" \
  || echo "[4] S3Storage DI with HTTP:        APPLIED"
```

---

## Fix 1: PresignedUrlProtocol Property on S3Storage

**File:** `src/Infrastructure/Infrastructure.S3/S3Storage.cs`

**Why:** AWS SDK generates `https://` presigned URLs. LocalStack only serves HTTP. Browsers get `ERR_SSL_PROTOCOL_ERROR` when trying to PUT to an HTTPS LocalStack URL.

**What to add:** A nullable `Protocol?` property that, when set, overrides the protocol on presigned URL requests.

### Step A: Add the property

Find the existing field declarations at the top of the `S3Storage` class:

```csharp
private readonly ITransferUtility _transferUtility;
private readonly ILogger<S3Storage> _logger;
```

Insert immediately after:

```csharp
/// <summary>
/// When set, overrides the protocol used in presigned URLs.
/// LocalStack only serves HTTP, so local dev sets this to Protocol.HTTP.
/// </summary>
public Protocol? PresignedUrlProtocol { get; init; }
```

### Step B: Apply the override in GetPreSignedUrlAsync

Find this block in `GetPreSignedUrlAsync`:

```csharp
// Since GetPreSignedURLAsync does not support cancellation directly, we are manually checking the token.
cancellationToken.ThrowIfCancellationRequested();

var url = await _s3Client.GetPreSignedURLAsync(getPreSignedUrlRequest);
```

Insert between the cancellation check and the `GetPreSignedURLAsync` call:

```csharp
if (PresignedUrlProtocol.HasValue)
{
    getPreSignedUrlRequest.Protocol = PresignedUrlProtocol.Value;
}
```

So the full block becomes:

```csharp
// Since GetPreSignedURLAsync does not support cancellation directly, we are manually checking the token.
cancellationToken.ThrowIfCancellationRequested();

if (PresignedUrlProtocol.HasValue)
{
    getPreSignedUrlRequest.Protocol = PresignedUrlProtocol.Value;
}

var url = await _s3Client.GetPreSignedURLAsync(getPreSignedUrlRequest);
```

### Required using (already present if Amazon.S3 is imported)

```csharp
using Amazon.S3;
```

`Protocol` is in the `Amazon.S3` namespace.

---

## Fix 2: ForcePathStyle on S3 Client

**File:** `src/Infrastructure/Infrastructure.Local.Core/Infrastructure/LocalStack/LocalStackExtensions.cs`

**Why:** By default, AWS SDK uses virtual-host-style URLs (`http://bucket-name.localhost:4566/key`). These DNS names don't resolve locally. Path-style (`http://localhost:4566/bucket-name/key`) works with LocalStack.

**What to add:** `ForcePathStyle = true` to the `AmazonS3Config` in `CreateS3Client`.

Find the `CreateS3Client` method:

```csharp
public static IAmazonS3 CreateS3Client(this LocalStackContainer container) =>
    new AmazonS3Client(
        new BasicAWSCredentials("test", "test"), // Any credentials will do
        new AmazonS3Config
        {
            ServiceURL = container.GetLocalStackServiceUrl(),
            UseHttp = true,
        }); // Config points to the container
```

Add `ForcePathStyle = true` to the config:

```csharp
public static IAmazonS3 CreateS3Client(this LocalStackContainer container) =>
    new AmazonS3Client(
        new BasicAWSCredentials("test", "test"), // Any credentials will do
        new AmazonS3Config
        {
            ServiceURL = container.GetLocalStackServiceUrl(),
            UseHttp = true,
            // LocalStack doesn't support virtual-host-style URLs (e.g. bucket.localhost:4566)
            ForcePathStyle = true,
        }); // Config points to the container
```

---

## Fix 3: CORS Configuration on S3 Buckets

**File:** `src/Infrastructure/Infrastructure.Local/Extensions/S3LifecycleHooksExtensions.cs`

**Why:** The browser makes a cross-origin PUT request from `http://localhost:4200` (frontend) to the LocalStack S3 endpoint. Without CORS headers, the browser blocks the request.

**What to add:** A `PutCORSConfigurationAsync` call after each bucket is created.

### Step A: Add using

Ensure this using is present at the top of the file:

```csharp
using Amazon.S3.Model;
```

### Step B: Add CORS config after bucket creation

Find the `CreateBucketsAsync` method:

```csharp
private static async ValueTask CreateBucketsAsync(IAmazonS3 client, IEnumerable<string> bucketNames)
{
    foreach (var bucketName in bucketNames)
    {
        await client.EnsureBucketExistsAsync(bucketName);
    }
}
```

Add the CORS configuration after `EnsureBucketExistsAsync`:

```csharp
private static async ValueTask CreateBucketsAsync(IAmazonS3 client, IEnumerable<string> bucketNames)
{
    foreach (var bucketName in bucketNames)
    {
        await client.EnsureBucketExistsAsync(bucketName);

        // Browser uploads from localhost:4200 require CORS on the S3 bucket
        await client.PutCORSConfigurationAsync(new PutCORSConfigurationRequest
        {
            BucketName = bucketName,
            Configuration = new CORSConfiguration
            {
                Rules =
                [
                    new CORSRule
                    {
                        AllowedOrigins = ["*"],
                        AllowedMethods = ["PUT", "GET", "HEAD"],
                        AllowedHeaders = ["*"],
                        ExposeHeaders = ["ETag"],
                    },
                ],
            },
        });
    }
}
```

---

## Fix 4: S3Storage DI Registration with HTTP Protocol

**File:** `src/Infrastructure/Infrastructure.Local/Infrastructure/LocalStack/LocalStackSetupInitializationHook.cs`

**Why:** Fix 1 adds the `PresignedUrlProtocol` property, but it only takes effect if the DI container creates `S3Storage` with the property set. Without this registration, the default (null) is used and presigned URLs remain HTTPS.

**What to add:** A singleton registration for `S3Storage` with `PresignedUrlProtocol = Protocol.HTTP`.

### Step A: Add usings

Ensure these are present at the top of the file:

```csharp
using Amazon.S3;
using Diligent.BoardsCloud.Infrastructure.S3;
using Microsoft.Extensions.Logging;
```

### Step B: Add DI registration

Find this block in the `AddServiceRegistration` lambda:

```csharp
var s3Client = _environment.CreateS3Client();
services.AddSingleton(s3Client);
services.AddSingleton<ITransferUtility>(_ => new TransferUtility(s3Client));

services.AddSingleton(_environment.CreateSecretsManagerClient());
```

Insert between the `ITransferUtility` registration and the `SecretsManager` registration:

```csharp
// LocalStack only serves HTTP; override presigned URL protocol so the browser can reach it
services.AddSingleton(sp => new S3Storage(
    sp.GetRequiredService<IAmazonS3>(),
    sp.GetRequiredService<ITransferUtility>(),
    sp.GetRequiredService<ILogger<S3Storage>>())
{
    PresignedUrlProtocol = Protocol.HTTP,
});
```

---

## Verification

After applying fixes, verify with a running backend:

1. **Start backend:** `dotnet run --project src/Apps/Web.Api.Local/Web.Api.Local.csproj`
2. **Check CORS headers on a bucket:**
   ```bash
   # Find the LocalStack port (random each startup)
   LOCALSTACK_PORT=$(docker ps --format '{{.Ports}}' | grep -o '[0-9]*->4566' | cut -d'-' -f1)
   # List buckets
   curl -s "http://localhost:$LOCALSTACK_PORT/" | grep -o '<Name>[^<]*</Name>'
   # Check CORS on first bucket (replace BUCKET_NAME)
   curl -s "http://localhost:$LOCALSTACK_PORT/BUCKET_NAME?cors" | grep AllowedMethod
   ```
3. **Browser test:** Log in at `http://localhost:4200` as `john-admin / pwd`, navigate to a book, upload a document. The upload should succeed without `ERR_SSL_PROTOCOL_ERROR` or CORS errors in the browser console.

## Background

- **Commit:** `f5fb266c8` on branch `yklin/bug-016-s3-local-dev-fix`
- **Original bug:** BUG-016 in `docs/backlog.md`
- **Root cause analysis:** `docs/debug-code-nextgen.md` — S3 / File Upload section
