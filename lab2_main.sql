create database [lab2];
go

use [lab2];

-- ATTRIBUTE

create table [type]
(
    [type_id] tinyint primary key,
    [name]    varchar(256) unique
);
insert into [type] ([type_id], [name])
values (0, 'null'),
       (1, 'string'),
       (2, 'number'),
       (3, 'boolean'),
       (4, 'array'),
       (5, 'object');
create table [attribute]
(
    [attribute_id] int identity primary key,
    [type_id]      tinyint references [type] ([type_id]),
    [name]         varchar(256) not null unique,
    [path]         varchar(256) not null
);

go
create or alter proc [createAttribute](@type varchar(255), @name varchar(255), @path varchar(255))
as
begin
    declare @type_id tinyint = (select [type_id] from [type] where [name] = @type);

    insert into [attribute] (type_id, name, path) values (@type_id, @name, @path);
end;
go

go
create or alter function [getAttributeValueById](@context nvarchar(max), @attribute_id int)
    returns nvarchar(max)
as
begin
    declare @type_id tinyint, @path varchar(256);

    select @type_id = [type_id], @path = [path] from [attribute] where [attribute_id] = @attribute_id;

    if @type_id is null or @path is null
        return null;

    declare @path_idx int = charindex('.', reverse(@path));
    declare @path_obj varchar(255) = left(@path, len(@path) - @path_idx);
    declare @path_key varchar(255) = right(@path, @path_idx - 1);

    declare @value nvarchar(max);

    select @value = value
    from openjson(@context, @path_obj)
    where [type] = @type_id
      and [key] = @path_key;

    return @value
end;
go
go
create or alter function [getAttributeValueByName](@context nvarchar(max), @name varchar(256))
    returns nvarchar(max)
as
begin
    declare @attribute_id int = (select [attribute_id] from [attribute] where [name] = @name);

    return [dbo].[getAttributeValueById](@context, @attribute_id);
end;
go

-- CONDITION

create table [compare]
(
    [compare_id] int identity primary key,
    [name]       varchar(256) not null unique
);
insert into [compare] (name)
values ('='),
       ('<>');
create table [condition]
(
    [condition_id] int identity primary key,
    [name]         varchar(256) not null unique,
    [compare_id]   int          not null references [compare] ([compare_id]),
    [left_id]      int          not null references [attribute] ([attribute_id]),
    [right_id]     int          not null references [attribute] ([attribute_id])
);

go
create or alter proc [createCondition](@name varchar(255), @compare varchar(255), @left_name varchar(255),
                                       @right_name varchar(255))
as
begin
    declare @compare_id int = (select [compare_id] from [compare] where [name] = @compare);
    declare @left_id int = (select [attribute_id] from [attribute] where [name] = @left_name);
    declare @right_id int = (select [attribute_id] from [attribute] where [name] = @right_name);

    insert into [condition] ([name], [compare_id], left_id, right_id) values (@name, @compare_id, @left_id, @right_id);
end;
go

go
create or alter function [executeConditionById](@context nvarchar(max), @condition_id int)
    returns bit
begin
    declare @compare_id int, @left_id int, @right_id int;

    select @compare_id = [compare_id], @left_id = [left_id], @right_id = [right_id]
    from [condition]
    where [condition_id] = @condition_id;

    if @left_id is null or @right_id is null
        return null;

    declare @left_value nvarchar(max) = [dbo].[getAttributeValueById](@context, @left_id);

    if @left_value is null
        return null;

    declare @right_value nvarchar(max) = [dbo].[getAttributeValueById](@context, @right_id);

    if @right_value is null
        return null

    declare @compare_name varchar(255) = (select [name] from [compare] where [compare_id] = @compare_id);

    if @compare_name = '='
        begin
            if @left_value = @right_value
                return 1;

            return 0;
        end;

    if @compare_name = '<>'
        begin
            if @left_value <> @right_value
                return 1;

            return 0;
        end;

    return 0;
end;
go
go
create or alter function [executeConditionByName](@context nvarchar(max), @condition_name varchar(255))
    returns bit
as
begin
    declare @condition_id int = (select [condition_id] from [condition] where [name] = @condition_name);

    return [dbo].[executeConditionById](@context, @condition_id);
end
go

-- RULE

create table [rule_algorithm]
(
    [algorithm_id] int identity primary key,
    [name]         varchar(255) not null unique
);
insert into [rule_algorithm] ([name])
values ('one'),
       ('all');
create table [rule]
(
    [rule_id]      int identity primary key,
    [name]         varchar(255) not null unique,
    [target_id]    int          not null
        references [condition] ([condition_id])
            on update cascade
            on delete cascade,
    [algorithm_id] int          not null
        references [rule_algorithm] ([algorithm_id])
            on update cascade
            on delete cascade
);
create table [rule_condition]
(
    [rule_id]      int not null references [rule] ([rule_id]),
    [condition_id] int not null references [condition] ([condition_id]),
    primary key ([rule_id], [condition_id])
);

go
create or alter proc [setRuleConditionsById](@rule_id int, @conditions nvarchar(max))
as
begin
    delete [rule_condition] where [rule_id] = @rule_id;

    insert into [rule_condition] ([rule_id], [condition_id])
    select @rule_id, [condition_id]
    from [condition]
    where [name] in (
        select [condition_name]
        from openjson(@conditions)
                      with ([condition_name] varchar(255) '$')
    );
end
go
go
create or alter proc [setRuleConditionsByName](@rule_name varchar(255), @conditions nvarchar(max))
as
begin
    declare @rule_id int = (select [rule_id] from [rule] where [name] = @rule_name);

    exec [setRuleConditionsById] @rule_id, @conditions;
end
go

go
create or alter proc [createRule](@name varchar(255), @target varchar(255), @algorithm varchar(255),
                                  @conditions nvarchar(max) = '[]')
as
begin
    declare @target_id int = (select [condition_id] from [condition] where [name] = @target);
    declare @algorithm_id int = (select [algorithm_id] from [rule_algorithm] where [name] = @algorithm);

    insert into [rule] ([name], [target_id], [algorithm_id])
    values (@name, @target_id, @algorithm_id);

    declare @rule_id int = scope_identity();

    exec [setRuleConditionsById] @rule_id, @conditions;
end
go

go
create or alter function [executeRuleById](@context nvarchar(max), @rule_id int)
    returns bit
as
begin
    declare @algorithm_id int = (select [algorithm_id] from [rule] where [rule_id] = @rule_id);
    declare @algorithm varchar(255) = (select [name] from [rule_algorithm] where [algorithm_id] = @algorithm_id);

    declare condition_cursor cursor for select [condition_id] from [rule_condition] where [rule_id] = @rule_id;
    declare @condition_id int;

    open condition_cursor;
    fetch next from condition_cursor into @condition_id;

    if (@@fetch_status <> 0)
        return null;

    declare @break bit, @result bit;

    while (@@fetch_status = 0 and @break is null)
        begin
            set @result = [dbo].[executeConditionById](@context, @condition_id);

            if @result is null or @result = 0 and @algorithm = 'all' or @result = 1 and @algorithm = 'one'
                begin
                    set @break = 1;
                end

            fetch next from condition_cursor into @condition_id;
        end

    close condition_cursor;
    deallocate condition_cursor;

    return @result;
end;
go
go
create or alter function [executeRuleByName](@context nvarchar(max), @rule_name varchar(255))
    returns bit
as
begin
    declare @rule_id int = (select [rule_id] from [rule] where [name] = @rule_name);

    return [dbo].[executeRuleById](@context, @rule_id);
end;
go

go
create or alter function [executeRuleTargetById](@context nvarchar(max), @rule_id int)
    returns bit
as
begin
    declare @target_id int = (select [target_id] from [rule] where [rule_id] = @rule_id);

    return [dbo].[executeConditionById](@context, @target_id);
end;
go
go
create or alter function [executeRuleTargetByName](@context nvarchar(max), @rule_name varchar(255))
    returns bit
as
begin
    declare @rule_id int = (select [rule_id] from [rule] where [name] = @rule_name);

    return [dbo].[executeRuleTargetById](@context, @rule_id);
end;
go

-- POLICY

create table [policy_algorithm]
(
    [algorithm_id] int identity primary key,
    [name]         varchar(255) not null unique
);
insert into [policy_algorithm] ([name])
values ('one'),
       ('all');
create table [policy]
(
    [policy_id]    int identity primary key,
    [name]         varchar(255) not null unique,
    [target_id]    int          not null
        references [condition] ([condition_id])
            on update cascade
            on delete cascade,
    [algorithm_id] int          not null
        references [policy_algorithm] ([algorithm_id])
            on update cascade
            on delete cascade
);
create table [policy_rule]
(
    [policy_id] int not null references [policy] ([policy_id]),
    [rule_id]   int not null references [rule] ([rule_id]),
    primary key ([policy_id], [rule_id])
);

go
create or alter proc [setPolicyRulesById](@policy_id int, @rules nvarchar(max))
as
begin
    delete [policy_rule] where [policy_id] = @policy_id;

    insert into [policy_rule] ([policy_id], [rule_id])
    select @policy_id, [rule_id]
    from [rule]
    where [name] in (
        select [rule_name]
        from openjson(@rules)
                      with ([rule_name] varchar(255) '$')
    );
end
go
go
create or alter proc [setPolicyRulesByName](@policy_name varchar(255), @rules nvarchar(max))
as
begin
    declare @policy_id int = (select [policy_id] from [policy] where [name] = @policy_name);

    exec [setPolicyRulesById] @policy_id, @rules;
end
go

go
create or alter proc [createPolicy](@name varchar(255), @target varchar(255), @algorithm varchar(255),
                                    @rules nvarchar(max) = '[]')
as
begin
    declare @target_id int = (select [condition_id] from [condition] where [name] = @target);
    declare @algorithm_id int = (select [algorithm_id] from [policy_algorithm] where [name] = @algorithm);

    insert into [policy] ([name], [target_id], [algorithm_id])
    values (@name, @target_id, @algorithm_id);

    declare @policy_id int = scope_identity();

    exec [setPolicyRulesById] @policy_id, @rules;
end
go

go
create or alter function [executePolicyById](@context nvarchar(max), @policy_id int)
    returns bit
as
begin
    declare @algorithm_id int = (select [algorithm_id] from [policy] where [policy_id] = @policy_id);
    declare @algorithm varchar(255) = (select [name] from [policy_algorithm] where [algorithm_id] = @algorithm_id);

    declare rule_cursor cursor for select [rule_id] from [policy_rule] where [policy_id] = @policy_id;
    declare @rule_id int;

    open rule_cursor;
    fetch next from rule_cursor into @rule_id;

    if (@@fetch_status <> 0)
        return null;

    declare @break bit, @result bit;

    while (@@fetch_status = 0 and @break is null)
        begin
            declare @rule_target_result bit = [dbo].[executeRuleTargetById](@context, @rule_id);

            if @rule_target_result = 1
                begin
                    set @result = [dbo].[executeRuleById](@context, @rule_id);

                    if @result is null or @result = 0 and @algorithm = 'all' or @result = 1 and @algorithm = 'one'
                        begin
                            set @break = 1;
                        end
                end

            fetch next from rule_cursor into @rule_id;
        end

    close rule_cursor;
    deallocate rule_cursor;

    return @result;
end;
go
go
create or alter function [executePolicyByName](@context nvarchar(max), @policy_name varchar(255))
    returns bit
as
begin
    declare @policy_id int = (select [policy_id] from [policy] where [name] = @policy_name);

    return [dbo].[executePolicyById](@context, @policy_id);
end;
go

go
create or alter function [executePolicyTargetById](@context nvarchar(max), @policy_id int)
    returns bit
as
begin
    declare @target_id int = (select [target_id] from [policy] where [policy_id] = @policy_id);

    return [dbo].[executeConditionById](@context, @target_id);
end;
go
go
create or alter function [executePolicyTargetByName](@context nvarchar(max), @policy_name varchar(255))
    returns bit
as
begin
    declare @policy_id int = (select [policy_id] from [policy] where [name] = @policy_name);

    return [dbo].[executePolicyTargetById](@context, @policy_id);
end;
go

-- POLICY_SET

create table [policyset_algorithm]
(
    [algorithm_id] int identity primary key,
    [name]         varchar(255) not null unique
);
insert into [policyset_algorithm] ([name])
values ('one'),
       ('all');
create table [policyset]
(
    [policyset_id] int identity primary key,
    [name]         varchar(255) not null unique,
    [target_id]    int          not null
        references [condition] ([condition_id])
            on update cascade
            on delete cascade,
    [algorithm_id] int          not null
        references [policyset_algorithm] ([algorithm_id])
            on update cascade
            on delete cascade
);
create table [policyset_policy]
(
    [policyset_id] int not null references [policyset] ([policyset_id]),
    [policy_id]    int not null references [policy] ([policy_id]),
    primary key ([policyset_id], [policy_id])
);

go
create or alter proc [setPolicySetPoliticsById](@policyset_id int, @politics nvarchar(max))
as
begin
    delete [policyset_policy] where [policyset_id] = @policyset_id;

    insert into [policyset_policy] ([policyset_id], [policy_id])
    select @policyset_id, [policy_id]
    from [policy]
    where [name] in (
        select [policy_name]
        from openjson(@politics)
                      with ([policy_name] varchar(255) '$')
    );
end
go
go
create or alter proc [setPolicySetPoliticsByName](@policyset_name varchar(255), @politics nvarchar(max))
as
begin
    declare @policyset_id int = (select [policyset_id] from [policyset] where [name] = @policyset_name);

    exec [setPolicySetPoliticsById] @policyset_id, @politics;
end
go

go
create or alter proc [createPolicySet](@name varchar(255), @target varchar(255), @algorithm varchar(255),
                                       @politics nvarchar(max) = '[]')
as
begin
    declare @target_id int = (select [condition_id] from [condition] where [name] = @target);
    declare @algorithm_id int = (select [algorithm_id] from [policyset_algorithm] where [name] = @algorithm);

    insert into [policyset] ([name], [target_id], [algorithm_id])
    values (@name, @target_id, @algorithm_id);

    declare @policyset_id int = scope_identity();

    exec [setPolicySetPoliticsById] @policyset_id, @politics;
end
go

go
create or alter function [executePolicySetById](@context nvarchar(max), @policyset_id int)
    returns bit
as
begin
    declare @algorithm_id int = (select [algorithm_id] from [policyset] where [policyset_id] = @policyset_id);
    declare @algorithm varchar(255) = (select [name] from [policyset_algorithm] where [algorithm_id] = @algorithm_id);

    declare policy_cursor cursor for select [policy_id] from [policyset_policy] where [policyset_id] = @policyset_id;
    declare @policy_id int;

    open policy_cursor;
    fetch next from policy_cursor into @policy_id;

    if (@@fetch_status <> 0)
        return null;

    declare @break bit, @result bit;

    while (@@fetch_status = 0 and @break is null)
        begin
            declare @policy_target_result bit = [dbo].[executePolicyTargetById](@context, @policy_id);

            if @policy_target_result = 1
                begin
                    set @result = [dbo].[executePolicyById](@context, @policy_id);

                    if @result is null or @result = 0 and @algorithm = 'all' or @result = 1 and @algorithm = 'one'
                        begin
                            set @break = 1;
                        end
                end

            fetch next from policy_cursor into @policy_id;
        end

    close policy_cursor;
    deallocate policy_cursor;

    return @result;
end;
go
go
create or alter function [executePolicySetByName](@context nvarchar(max), @policyset_name varchar(255))
    returns bit
as
begin
    declare @policyset_id int = (select [policyset_id] from [policyset] where [name] = @policyset_name);

    return [dbo].[executePolicySetById](@context, @policyset_id);
end;
go

go
create or alter function [executePolicySetTargetById](@context nvarchar(max), @policyset_id int)
    returns bit
as
begin
    declare @target_id int = (select [target_id] from [policyset] where [policyset_id] = @policyset_id);

    return [dbo].[executeConditionById](@context, @target_id);
end;
go
go
create or alter function [executePolicySetTargetByName](@context nvarchar(max), @policyset_name varchar(255))
    returns bit
as
begin
    declare @policyset_id int = (select [policyset_id] from [policyset] where [name] = @policyset_name);

    return [dbo].[executePolicySetTargetById](@context, @policyset_id);
end;
go

-- ABAC

go
create or alter function [executeAbac](@context nvarchar(max))
    returns bit
as
begin
    declare @date_now datetime = getdate();

    declare @dw nvarchar(max) = '{}';

    set @dw = json_modify(@dw, '$.current', datepart(dw, @date_now));
    set @dw = json_modify(@dw, '$.sun', 1);
    set @dw = json_modify(@dw, '$.mon', 2);
    set @dw = json_modify(@dw, '$.tue', 3);
    set @dw = json_modify(@dw, '$.wed', 4);
    set @dw = json_modify(@dw, '$.thu', 5);
    set @dw = json_modify(@dw, '$.fri', 6);
    set @dw = json_modify(@dw, '$.sat', 7);

    declare @time nvarchar(max) = '{}';

    set @time = json_modify(@time, '$.second', datepart(second, @date_now));
    set @time = json_modify(@time, '$.minute', datepart(minute, @date_now));
    set @time = json_modify(@time, '$.hour', datepart(hour, @date_now));

    declare @date nvarchar(max) = '{}';

    set @date = json_modify(@date, '$.day', day(@date_now));
    set @date = json_modify(@date, '$.month', month(@date_now));
    set @date = json_modify(@date, '$.year', year(@date_now));

    declare @env nvarchar(max) = '{}';

    set @env = json_modify(@env, '$.dw', json_query(@dw));
    set @env = json_modify(@env, '$.time', json_query(@time));
    set @env = json_modify(@env, '$.date', json_query(@date));

    set @context = json_modify(@context, '$.env', json_query(@env));
    set @context = json_modify(@context, '$.enum', json_query('{
        "const": {
            "true": true,
            "false": false
        },
        "object": {
            "user": "user",
            "office": "office",
            "position": "position",
            "employee": "employee",
            "status": "status",
            "task": "task",
            "role": "role",
            "member": "member"
        },
        "action": {
            "select": "select",
            "create": "create",
            "update": "update",
            "delete": "delete"
        },
        "service": {
            "task": "task"
        }
    }'));

    declare policyset_cursor cursor for select [policyset_id] from [policyset];
    declare @policyset_id int;

    open policyset_cursor;
    fetch next from policyset_cursor into @policyset_id;

    if (@@fetch_status <> 0)
        return 0;

    declare @break bit, @result bit;

    while (@@fetch_status = 0 and @break is null)
        begin
            declare @policyset_target_result bit = [dbo].[executePolicySetTargetById](@context, @policyset_id);

            if @policyset_target_result = 1
                begin
                    set @result = [dbo].[executePolicySetById](@context, @policyset_id);

                    if @result is null or @result = 0
                        begin
                            set @break = 1;
                        end
                end

            fetch next from policyset_cursor into @policyset_id;
        end

    close policyset_cursor;
    deallocate policyset_cursor;

    if @result = 1
        return 1;

    return 0;
end;
go

-- DATA

create table [user]
(
    [user_id] int identity primary key,
    [name]    varchar(256) not null
);
create table [office]
(
    [office_id] int identity primary key,
    [name]      varchar(256) not null unique
);
create table [position]
(
    [position_id] int identity primary key,
    [name]        varchar(256) not null unique
);
create table [employee]
(
    [user_id]     int not null
        references [user] ([user_id])
            on update cascade
            on delete cascade,
    [office_id]   int not null
        references [office] ([office_id])
            on update cascade
            on delete cascade,
    [position_id] int not null
        references [position] ([position_id])
            on update cascade
            on delete cascade,

    primary key ([user_id], [office_id], [position_id])
);
create table [status]
(
    [status_id] int identity primary key,
    [title]     varchar(256) not null unique
);
create table [task]
(
    [task_id]   int identity primary key,
    [title]     varchar(256) not null,
    [status_id] int          not null
        references [status] ([status_id])
            on update cascade
            on delete cascade
);
create table [role]
(
    [role_id] int identity primary key,
    [title]   varchar(256) not null unique
);
create table [member]
(
    [task_id] int not null
        references [task] ([task_id])
            on update cascade
            on delete cascade,
    [user_id] int not null
        references [user] ([user_id])
            on update cascade
            on delete cascade,
    [role_id] int not null
        references [role] ([role_id])
            on update cascade
            on delete cascade,

    primary key (task_id, user_id, role_id)
);

-- TASKS
create or alter view [tasks]
as
select [task_id],
       [title],
       (
           select *
           from (
                    select *
                    from [status]
                    where [status_id] = [task].[status_id]
                ) [status]
           for json auto
       )                     as [status],
       json_query((
                      select *
                      from (
                               select [user_id]
                               from [member]
                               where [task_id] = [task].[task_id]
                                 and [role_id] = (select [role_id] from [role] where [title] = 'owner')
                           ) [owner]
                      for json auto
                  ), '$[0]') as [owner],
       (
           select *
           from (
                    select (
                               select *
                               from (
                                        select *
                                        from [user]
                                        where [user_id] = [member].[user_id]
                                    ) [user]
                               for json auto
                           ) as [user],
                           (
                               select *
                               from (
                                        select *
                                        from [role]
                                        where [role_id] = [member].[role_id]
                                    ) [role]
                               for json auto
                           ) as [role]
                    from [member]
                    where [task_id] = [task].[task_id]
                ) [member]
           for json auto
       )                     as [members]
from [task];

select * from tasks;

exec [createAttribute] 'number', 'dw_curr', '$.env.dw.current';
exec [createAttribute] 'number', 'dw_sun', '$.env.dw.sun';
exec [createAttribute] 'number', 'dw_mon', '$.env.dw.mon';
exec [createAttribute] 'number', 'dw_tue', '$.env.dw.tue';
exec [createAttribute] 'number', 'dw_wed', '$.env.dw.wed';
exec [createAttribute] 'number', 'dw_thu', '$.env.dw.thu';
exec [createAttribute] 'number', 'dw_fri', '$.env.dw.fri';
exec [createAttribute] 'number', 'dw_sat', '$.env.dw.sat';

exec [createAttribute] 'number', 'time_second', '$.env.time.second';
exec [createAttribute] 'number', 'time_minute', '$.env.time.minute';
exec [createAttribute] 'number', 'time_hour', '$.env.time.hour';

exec [createAttribute] 'number', 'date_day', '$.env.date.day';
exec [createAttribute] 'number', 'date_month', '$.env.date.month';
exec [createAttribute] 'number', 'date_year', '$.env.date.year';

exec [createAttribute] 'boolean', 'true', '$.enum.const.true';
exec [createAttribute] 'boolean', 'false', '$.enum.const.false';

exec [createAttribute] 'string', 'user', '$.enum.object.user';
exec [createAttribute] 'string', 'task', '$.enum.object.task';
exec [createAttribute] 'string', 'member', '$.enum.object.member';

exec [createAttribute] 'string', 'select', '$.enum.action.select';
exec [createAttribute] 'string', 'create', '$.enum.action.create';
exec [createAttribute] 'string', 'update', '$.enum.action.update';
exec [createAttribute] 'string', 'delete', '$.enum.action.delete';

exec [createAttribute] 'string', 'service_task', '$.enum.service.task';

exec [createCondition] 'isSun', '=', 'dw_curr', 'dw_sun';
exec [createCondition] 'isMon', '=', 'dw_curr', 'dw_mon';
exec [createCondition] 'isTue', '=', 'dw_curr', 'dw_tue';
exec [createCondition] 'isWed', '=', 'dw_curr', 'dw_wed';
exec [createCondition] 'isThu', '=', 'dw_curr', 'dw_thu';
exec [createCondition] 'isFri', '=', 'dw_curr', 'dw_fri';
exec [createCondition] 'isSat', '=', 'dw_curr', 'dw_sat';

exec [createCondition] 'always', '=', 'true', 'true';

exec [createRule] 'isWorkDay', 'always', 'one', '["isMon","isTue","isWed","isThu","isFri"]';

exec [createAttribute] 'string', 'action_name', '$.action.name';

exec [createCondition] 'isSelect', '=', 'action_name', 'select';
exec [createCondition] 'isCreate', '=', 'action_name', 'create';
exec [createCondition] 'isUpdate', '=', 'action_name', 'update';
exec [createCondition] 'isDelete', '=', 'action_name', 'delete';

exec [createAttribute] 'number', 'user_id', '$.user_data.user_id';
exec [createAttribute] 'number', 'owner_id', '$.curr_task.owner.user_id';

exec [createCondition] 'isOwner', '=', 'user_id', 'owner_id';

exec [createRule] 'isMainMember', 'always', 'all', '["isOwner"]';

exec [createPolicy] 'selectTask', 'isSelect', 'all', '["isWorkDay","isMainMember"]';
exec [createPolicy] 'createTask', 'isCreate', 'all', '["isWorkDay"]';
exec [createPolicy] 'updateTask', 'isUpdate', 'all', '["isWorkDay","isMainMember"]';
exec [createPolicy] 'deleteTask', 'isDelete', 'all', '["isWorkDay","isMainMember"]';

exec [createAttribute] 'string', 'object_name', '$.object.name';

exec [createCondition] 'isTask', '=', 'object_name', 'task';

exec [createPolicySet] 'task', 'isTask', 'one', '["selectTask","createTask","updateTask","deleteTask"]';

-- INIT

insert into [user] ([name])
values
    ('test1'),
    ('test2');
insert into [status] ([title])
values ('open'),
       ('close');
insert into [role] ([title])
values ('owner'),
       ('watcher');

go
create or alter function [GetTask](@task_id int)
    returns nvarchar(max)
as
begin
    declare @result nvarchar(max);

    select @result = json_query(
            (select * from (select * from [tasks] where [task_id] = @task_id) [tasks] for json auto),
            '$[0]'
        );

    return @result;
end;
go

-- Select TASK
go
create or alter function [GetContextForSelect](@task_id int, @user_data nvarchar(max))
    returns nvarchar(max)
as
begin
    declare @curr_task nvarchar(max) = [dbo].[GetTask](@task_id);

    declare @context nvarchar(max) = '{
        "service": { "name": "task" },
        "object": { "name": "task" },
        "action": { "name": "select" }
    }';

    set @context = json_modify(@context, '$.user_data', json_query(@user_data));
    set @context = json_modify(@context, '$.curr_task', json_query(@curr_task));

    return @context;
end;
go

go
create or alter function [SelectTask](@user_data nvarchar(max))
    returns table
        as
        return
        select *
        from [tasks]
        where [dbo].[executeAbac]([dbo].[GetContextForSelect]([task_id], @user_data)) = 1;
go

-- Create TASK
go
create or alter proc [CreateTask] @user_data nvarchar(max), @task_data nvarchar(max)
as
begin
    declare @context nvarchar(max) = '{
        "service": { "name": "task" },
        "object": { "name": "task" },
        "action": { "name": "create" }
    }';

    set @context = json_modify(@context, '$.user_data', json_query(@user_data));
    set @context = json_modify(@context, '$.task_data', json_query(@task_data));

    if [dbo].[executeAbac](@context) = 0
        begin
            throw 51000, 'Недостоточно прав для создания задачи!', 1;
        end

    begin transaction;
    insert into [task] ([title], [status_id])
    select [title], [status_id]
    from openjson(@task_data) with ([title] varchar(256) '$.title',[status_id] int '$.status_id');

    declare @task_id int = scope_identity();

    insert into [member] ([task_id], [user_id], [role_id])
    select @task_id, [user_id], (select [role_id] from [role] where [title] = 'owner')
    from openjson(@task_data) with ([user_id] int '$.user_id');
    commit;
end;
go

-- Update TASK
go
create or alter proc [UpdateTask] @task_id int, @user_data nvarchar(max), @task_data nvarchar(max)
as
begin
    declare @curr_task nvarchar(max) = [dbo].[GetTask](@task_id);

    declare @context nvarchar(max) = '{
        "service": { "name": "task" },
        "object": { "name": "task" },
        "action": { "name": "update" }
    }';

    set @context = json_modify(@context, '$.user_data', json_query(@user_data));
    set @context = json_modify(@context, '$.curr_task', json_query(@curr_task));
    set @context = json_modify(@context, '$.task_data', json_query(@task_data));

    if [dbo].[executeAbac](@context) = 0
        begin
            throw 51000, 'Недостоточно прав для обновления задачи!', 1;
        end

    update [task]
    set [title]     = [new].[title],
        [status_id] = [new].[status_id]
    from [task]
             join openjson(@task_data) with ([title] varchar(256) '$.title',[status_id] int '$.status_id') as [new]
                  on [task_id] = @task_id;
end;
go

-- Delete TASK
go
create or alter proc [DeleteTask] @task_id int, @user_data nvarchar(max)
as
begin
    declare @curr_task nvarchar(max) = [dbo].[GetTask](@task_id);

    declare @context nvarchar(max) = '{
        "service": { "name": "task" },
        "object": { "name": "task" },
        "action": { "name": "delete" }
    }';

    set @context = json_modify(@context, '$.user_data', json_query(@user_data));
    set @context = json_modify(@context, '$.curr_task', json_query(@curr_task));

    if [dbo].[executeAbac](@context) = 0
        begin
            throw 51000, 'Недостоточно прав для удаления задачи!', 1;
        end

    delete [task] where [task_id] = @task_id;
end;
go

create login [AppLogin] with password = '5Y2Ts3@URv1hZlOi';
create user [AppUser] for login [AppLogin];
create application role [AppRole]
    with password = '5Y2Ts3@URv1hZlOi';

grant select on object::[dbo].[SelectTask] to [AppRole];
grant execute on object::[dbo].[CreateTask] to [AppRole];
grant execute on object::[dbo].[UpdateTask] to [AppRole];
grant execute on object::[dbo].[DeleteTask] to [AppRole];
