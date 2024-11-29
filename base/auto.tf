# Automation goes here

locals {  
  // Load and merge all user definitions from YAML files into a single map  
  users = merge(  
    [  
      for f in fileset(path.module, "./resources/users/*.yaml") :   
      yamldecode(file("${path.module}/${f}"))  
    ]...  
  )  

  // Load and merge all group definitions from YAML files into a single map  
  groups = merge(  
    [  
      for f in fileset(path.module, "./resources/groups/*.yaml") :   
      yamldecode(file("${path.module}/${f}"))  
    ]...  
  )  

  // Define group memberships by creating a map that associates users with groups  
  memberships = merge(  
    flatten([  
      for group_name, group_attrs in local.groups : [  
        for user_email in group_attrs.members : {  
          "${group_name}_${user_email}" = {  
            user  = user_email,  
            group = group_name  
          }  
        }  
      ] if group_attrs.members != null  
    ])...  
  )  

  // Load and merge all permission set definitions from YAML files into a single map  
  permission_sets = merge(  
    [  
      for f in fileset(path.module, "./resources/permission_sets/*.yaml") :   
      yamldecode(file("${path.module}/${f}"))  
    ]...  
  )  

  // Define managed policy attachments for each permission set  
  managed_policies = merge(  
    flatten([  
      for ps_name, ps_attrs in local.permission_sets : [  
        for policy in try(ps_attrs.managed_policies, []) : {  
          "${ps_name}_${policy}" = {  
            permission_set = ps_name,  
            policy = policy  
          }  
        }  
      ]  
    ])...  
  )  

  // Define customer managed policy attachments for each permission set  
  customer_managed_policies = merge(  
    flatten([  
      for ps_name, ps_attrs in local.permission_sets : [  
        for policy_tuple in try(ps_attrs.customer_managed_policies, []) : {  
          "${ps_name}_${policy_tuple.policy}" = {  
            permission_set = ps_name,  
            policy = policy_tuple.policy,  
            path = try(policy_tuple.path, "/")  
          }  
        }  
      ]  
    ])...  
  )  

  // Define account assignments for each group  
  accounts = merge(  
    flatten([  
      for group_name, group_attrs in local.groups : [  
        for acc_name, acc_attrs in group_attrs.accounts : [  
          for perm_set in acc_attrs.permission_set : {  
            "${group_name}_${acc_name}_${perm_set}" = {  
              account = acc_name,  
              group = group_name,  
              permission_set = perm_set  
            }  
          }  
        ]  
      ] if group_attrs.accounts != null  
    ])...  
  )  
}  

data "aws_ssoadmin_instances" "sso" {}  

resource "aws_identitystore_group" "this" {  
  // Create AWS IdentityStore groups for each group defined in the local variable  
  for_each = local.groups  

  display_name      = each.key  
  description       = each.value.description  
  identity_store_id = data.aws_ssoadmin_instances.sso.identity_store_ids[0]  
}  

resource "aws_identitystore_user" "this" {  
  // Create AWS IdentityStore users for each user defined in the local variable  
  for_each = local.users  

  identity_store_id = data.aws_ssoadmin_instances.sso.identity_store_ids[0]  
  user_name         = each.key  

  name {  
    given_name       = each.value.name.given_name  
    family_name      = each.value.name.family_name  
    middle_name      = try(each.value.name.middle_name, null)  
    formatted        = try(each.value.name.formatted, null)  
    honorific_prefix = try(each.value.name.honorific_prefix, null)  
    honorific_suffix = try(each.value.name.honorific_suffix, null)  
  }  

  display_name = try(  
    "${each.value.name.given_name} ${each.value.name.family_name} (${each.value.organization})",  
    "${each.value.name.given_name} ${each.value.name.family_name}"  
  )  

  title              = try(each.value.title, null)  
  preferred_language = try(each.value.preferred_language, null)  

  // Define dynamic block for phone numbers  
  dynamic "phone_numbers" {  
    for_each = try(each.value.phone_numbers, {})  

    // Provision phone numbers associated with the user  
    content {  
      primary = phone_numbers.value.primary  
      type    = phone_numbers.value.type  
      value   = phone_numbers.key  
    }  
  }  

  // Define the primary email address for the user  
  emails {  
    type    = "main"  
    value   = try(each.value.email, each.key)  
    primary = true  
  }  
}  

resource "aws_identitystore_group_membership" "this" {  
  // Create group memberships for each user-group association defined in the local variable  
  for_each = local.memberships  
  
  identity_store_id = data.aws_ssoadmin_instances.sso.identity_store_ids[0]  
  group_id          = aws_identitystore_group.this[each.value.group].group_id  
  member_id         = aws_identitystore_user.this[each.value.user].user_id  
}  

data "aws_ssoadmin_instances" "this" {}  

resource "aws_ssoadmin_permission_set" "this" {  
  // Create permission sets for each permission set defined in the local variable  
  for_each = local.permission_sets  

  name         = each.key  
  description  = try(each.value.description, null)  
  instance_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]  

  session_duration = try(each.value.session_duration, "PT1H")  
}  

resource "aws_ssoadmin_managed_policy_attachment" "this" {  
  // Attach AWS managed policies to each permission set  
  for_each = local.managed_policies  

  instance_arn        = tolist(data.aws_ssoadmin_instances.this.arns)[0]  
  managed_policy_arn  = "arn:aws:iam::aws:policy/${each.value.policy}"  
  permission_set_arn  = aws_ssoadmin_permission_set.this[each.value.permission_set].arn  
}  

resource "aws_ssoadmin_customer_managed_policy_attachment" "this" {  
  // Attach customer-managed policies to each permission set  
  for_each = local.customer_managed_policies  

  instance_arn               = tolist(data.aws_ssoadmin_instances.this.arns)[0]  
  permission_set_arn         = aws_ssoadmin_permission_set.this[each.value.permission_set].arn  
  customer_managed_policy_reference {  
    name = each.value.policy  
    path = each.value.path  
  }  
}  

resource "aws_ssoadmin_account_assignment" "this" {  
  // Create account assignments for each account-group-permission set association  
  depends_on       = [aws_ssoadmin_permission_set.this]  
  for_each         = local.accounts  

  instance_arn     = tolist(data.aws_ssoadmin_instances.this.arns)[0]  
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn  

  principal_id     = aws_identitystore_group.this[each.value.group].group_id  
  principal_type   = "GROUP"  

  target_id        = each.value.account  
  target_type      = "AWS_ACCOUNT"  
}  

output "identity_store_id" {  
  // Output the ID of the AWS Identity Store used in this module  
  value = data.aws_ssoadmin_instances.sso.identity_store_ids[0]  
}  

output "instance_arn" {  
  // Output the ARN of the AWS SSO instance  
  value = tolist(data.aws_ssoadmin_instances.this.arns)[0]  
}  

output "debug" {  
  // Debug output to inspect values (uncomment local.accounts during debugging)  
  value = null // `local.accounts` can be uncommented during debugging to inspect values  
}