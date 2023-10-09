-- створити загальгу таблиці, в якій будуть об'єдні всі данні 
with tt as(
	select 
		gp.user_id, 
		gp.game_name, 
		gp.payment_date, 
		date(date_trunc('month', payment_date)) as first_month_day,
		max(payment_date) over (partition by gp.user_id) as max_date,
		min(payment_date) over (partition by gp.user_id) as min_date,
		date_part('month', gp.payment_date) as payment_month,
		gp.revenue_amount_usd,
		gpu."language",
		gpu.has_older_device_model,
		gpu.age 
	from games_payments as gp  
	
	left join games_paid_users gpu  
		on gp.user_id = gpu.user_id
	
	where gp.game_name = 'game 3'
	order by user_id, payment_date
),

-- розрахувати максимальну і мінімальну дати існування юзера в грі
dates as(
	select distinct on (user_id, max_date, min_date)
		user_id, 
		max_date,
		min_date
	from tt
	group by user_id, max_date, min_date
	order by user_id, max_date, min_date
),

-- розрахувати загальну суму доходу
us as(
	select
		user_id, 
		game_name,
		"language",
		has_older_device_model,
		age,
		first_month_day,
		payment_month,
		sum(revenue_amount_usd) as rev
	from tt
	group by user_id, game_name, "language", has_older_device_model, age, payment_month, first_month_day
	order by user_id, payment_month, first_month_day
),

-- розрахувати різницю в доходах
ust as(
	select
		user_id,
		game_name,
		"language",
		has_older_device_model,
		age,
		first_month_day,
		payment_month,	
		payment_month - lag(payment_month) over (partition by user_id order by payment_month) as month_dif,
		rev,
		rev - lag(rev) over (partition by user_id order by payment_month) as rev_dif
					
	from us
	group by user_id, payment_month, rev, game_name, "language", has_older_device_model, age, first_month_day
),

-- допоміжні розрахунки для визначення MRR

cte as(
	select 
		user_id,
		payment_month,
		rev,
		sum(case when month_dif > 1  then 1 else 0 end) over (partition by user_id order by payment_month) as group_id
	from ust

),

-- розрахунок MRR
mrr as(
	select 
		user_id,
	    payment_month,
	    rev,
	    lag(payment_month) over (partition by user_id order by payment_month) as previous_month,
	    rev - lag(rev) over (partition by user_id order by payment_month) as difference,
	    sum(rev) over (partition by user_id, group_id order by payment_month) as mrr_cumulative
	from
	    cte
)

select 
	ust.user_id,
	ust.game_name,
	ust."language",
	ust.has_older_device_model,
	ust.age,
	d.max_date,
	d.min_date,
	ust.first_month_day,
	ust.payment_month,
	ust.rev,
	ust.month_dif,
	ust.rev_dif,
	mrr.mrr_cumulative,
	
	case
		when ust.month_dif > 1 and lead(ust.month_dif) over (partition by ust.user_id order by ust.payment_month) = 1
		then 1 else 0
	end as ret_af_ch,
	
	case
		when ((ust.month_dif isnull and  lead(ust.month_dif) over (partition by ust.user_id order by ust.payment_month) = 1) or ust.month_dif = 1) 
			or (ust.month_dif > 1 and lead(ust.month_dif) over (partition by ust.user_id order by ust.payment_month) = 1) 
		then 1 else 0
	end as mrr_group,
	
	
	case
		when (ust.payment_month = date_part('month', d.max_date) and lag(ust.month_dif) over (partition by ust.user_id order by ust.payment_month) = 1)
			or (ust.month_dif = 1 and lead(ust.month_dif) over (partition by ust.user_id order by ust.payment_month) > 1)		
		then 1 else 0
	end as total_mrr_group,
	
	case
		when (date_part('month', d.min_date) = ust.payment_month or ust.month_dif > 1) and lead(ust.month_dif) over (partition by ust.user_id order by ust.payment_month) = 1
		then 1 else 0
	end as new_mrr_group
	
	
		
from ust as ust



left join mrr as mrr
	on ust.user_id = mrr.user_id and ust.payment_month = mrr.payment_month

left join dates as d
	on ust.user_id = d.user_id

