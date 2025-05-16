output "eip" {
	value = aws_eip.eip.public_ip
}

output "sns_arn" {
	value = aws_sns_topic.image_processed.arn
}
