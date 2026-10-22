output "s3_bucket_name" {
  description = "The name of the S3 media bucket"
  value       = aws_s3_bucket.media.bucket
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 media bucket"
  value       = aws_s3_bucket.media.arn
}

output "s3_bucket_regional_domain_name" {
  description = "The regional domain name of the S3 media bucket"
  value       = aws_s3_bucket.media.bucket_regional_domain_name
}

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution serving media"
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "cloudfront_distribution_id" {
  description = "The ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn.id
}

output "cloudfront_distribution_arn" {
  description = "The ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn.arn
}
