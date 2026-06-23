# OU Structure

```text
Root - r-073p
├── Security - ou-073p-zix212u6
│   ├── Audit Account
│   └── Log Archive Account
│
├── Sandbox - ou-073p-bvjddry6
│   └── Sandbox Account
│
├── Infrastructure - ou-073p-mn40qfn7
│   ├── Networking Account
│   └── SharedServices Account
│
└── Workloads - ou-073p-ce450az5
    ├── Workloads-NonProd -  ou-073p-25sjfw18
    │   └── (future: Dev, Test, UAT accounts)
    └── Workloads-Prod - ou-073p-npqejn0x
        └── (future: Prod accounts)
```

## Commands

```sh
aws organizations list-roots --query 'Roots[*].{Id:Id, Name:Name}' --output table
aws organizations list-organizational-units-for-parent --parent-id r-073p --query 'OrganizationalUnits[*].{Id:Id, Name:Name}' --output table
aws organizations list-organizational-units-for-parent --parent-id  ou-073p-mn40qfn7 --query 'OrganizationalUnits[*].{Id:Id, Name:Name}' --output table
```
