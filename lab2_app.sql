use [lab2];

exec sp_setapprole
    @rolename = 'AppRole',
    @password = '5Y2Ts3@URv1hZlOi';

select * from [dbo].[SelectTask]('{"user_id": 2}');
exec [dbo].[CreateTask] '{"user_id": 2}', '{"title": "Hello, World!", "status_id": 1, "user_id": 2}';
exec [dbo].[UpdateTask] 14, '{"user_id": 2}', '{"title": "Hello", "status_id": 1}';
exec [dbo].[DeleteTask] 14, '{"user_id": 2}';
