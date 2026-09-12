/*
 * FIXTURE: deliberately insecure Terraform used by scripts/verify.sh.
 * Expected findings: public-read ACL, world-open ingress, unencrypted bucket.
 * The formatting is also intentionally wrong so `terraform fmt -check` fires.
 */
resource "aws_s3_bucket" "public" {
  bucket = "demo-insecure-bucket"
}

resource "aws_s3_bucket_acl" "public" {
    bucket = aws_s3_bucket.public.id
    acl = "public-read"
}

resource "aws_security_group" "open" {
  name = "demo-open-sg"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
