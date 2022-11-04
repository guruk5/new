 variable "aws_region" {
    description = "Region in which AWS Resources to be created"
    type = string
    default = "ap-south-1"
}

variable "name_prefix" {
    description = "Name prefix for resources on AWS"
    type        = string
    default     = "wipo"
}

variable "vpc_cidr" {
    description = "The CIDR Block for the VPC"
    type = string 
    default = "10.41.201.0/24"
}

#variable "availability_zones" {
#   type        = list(string)
#   description = "List of Availability Zones (e.g. `['us-east-1a', 'us-east-1b', 'us-east-1c']`)"
#}

variable "cidr_block" {
    description = "Cidr for data subnet"
    type = string
    default = "10.41.201.0/24"
}

variable "retention" {
    description = "Number of days of Log retention of CloudWatch" 
    type = string
    default = "7"
}
