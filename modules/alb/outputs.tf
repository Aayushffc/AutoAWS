output "alb_id" {
  description = "The ID of the Application Load Balancer"
  value       = aws_lb.this.id
}

output "alb_arn" {
  description = "The ARN of the Application Load Balancer"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.this.dns_name
}

output "target_group_arn" {
  description = "The ARN of the primary target group forwarding to port 3000"
  value       = aws_lb_target_group.this.arn
}

output "http_listener_arn" {
  description = "The ARN of the HTTP:80 redirect listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "The ARN of the HTTPS:443 listener"
  value       = aws_lb_listener.https.arn
}
