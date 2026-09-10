# When not to use this

Read this before pointing it at anything that matters.

## What Microsoft offers instead

**Auto-shutdown** on a virtual machine schedules a daily shutdown per machine, from the portal, free.
If one machine needs one shutdown time and nobody needs it started again, use that and stop reading.

**`Microsoft.ComputeSchedule`** performs batched Start, Deallocate and Hibernate across an estate,
handles throttling and retries for you, and takes schedules up to fourteen days ahead. If you already
know exactly which machines to act on and something else keeps that list current, use it directly.

This tool exists for what neither covers: deciding *which* machines should be off, guarding the
decision, and proving afterwards what it saved. It hands the power operation to Azure.

## Do not use for

| Case | Why | Do this instead |
|---|---|---|
| Domain controllers | Replication and time service break in ways that surface days later, on other machines | Leave them running; they are cheap relative to the failure |
| Anything holding a quorum — cluster nodes, etcd, ZooKeeper, availability groups | Stopping a member can cost the quorum and take the whole service with it, and starting it back does not always heal | Scale the workload, do not power it |
| Machines with a licence check on boot | Some licences count activations or need a licence server that is itself asleep | Confirm the licensing model first |
| Anything under a customer SLA | An outage you scheduled is still an outage you caused | Keep it out of scope; there is no tag that makes this safe |
| Production, generally | This tool is built for development and test estates and its defaults assume that | If you must, arm it on one resource group and read a month of the workbook first |
| Machines somebody is logged into right now | Version 1 cannot see guest sessions | Use the snooze once self-service ships, or exclude the machine |

## Things the tool cannot see

- **Whether anybody is using the machine.** Version 1 reads power state and tags, not sessions,
  processes or open files. A machine that looks idle to Azure can have somebody working on it.
- **What a workload needs on shutdown.** A graceful OS shutdown is not the same as a clean
  application shutdown. Databases, queues and anything mid-transaction need their own handling.
- **Why a machine was tagged.** A schedule that was right a year ago may be wrong now, and nothing in
  the tag records who chose it or why.
- **Dependencies between machines.** Starting an application server before its database is not
  something this tool knows to order.
- **What a start costs.** Since 1 June 2025 Azure bills a five-minute minimum per start, so a schedule
  that flaps costs money as well as being wrong.

## The disclaimer that matters

This is MIT-licensed software given away for free. It stops virtual machines, which means it can stop
one you needed. The guards exist because that is a real risk, not because it is unlikely: it ships
disarmed, it touches nothing that is not explicitly tagged, and it refuses a run that would affect
more machines than you allowed.

Read a week of the workbook before you arm it. If a machine appears in that report and you are not
sure, it does not belong in scope.
