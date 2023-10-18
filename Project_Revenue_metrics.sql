-- create a new table, with the main data about revenue(user_id, date, total revenue. Choose only game 3 (the most completed dataset)
with users_pivot_table as(
	select 
		gp.user_id, 
		date(date_trunc('month', payment_date)) as first_month_day,
		max(payment_date) over (partition by gp.user_id) as max_date,
		min(payment_date) over (partition by gp.user_id) as min_date,
		date_part('month', gp.payment_date) as payment_month,
		gp.revenue_amount_usd
	from games_payments as gp  
	where gp.game_name = 'game 3'
	order by user_id, date(date_trunc('month', payment_date))
),

-- mention the max and min date of user's activity in the game
dates_table as(
	select distinct on (user_id, max_date, min_date)
		user_id, 
		max_date,
		min_date
	from users_pivot_table
	group by user_id, max_date, min_date
	order by user_id, max_date, min_date
),

-- calculated the total revenue, grouped by users and payment_month
revenue_table as(
	select
		user_id, 
		first_month_day,
		payment_month,
		sum(revenue_amount_usd) as rev
	from users_pivot_table
	group by user_id, payment_month, first_month_day
	order by user_id, payment_month, first_month_day
),

-- calculate the revenue's difference
rev_dif_table as(
	select
		user_id,
		first_month_day,
		payment_month,	
		payment_month - lag(payment_month) over (partition by user_id order by payment_month) as month_dif,
		rev,
		rev - lag(rev) over (partition by user_id order by payment_month) as rev_dif
					
	from revenue_table
	group by user_id, first_month_day, payment_month, rev
),

-- additional calculation for MRR. MRR - the revenue from users, who paid more then 2 and difference between months = 1

cte as(
	select 
		user_id,
		payment_month,
		rev,
		sum(case when month_dif > 1  then 1 else 0 end) over (partition by user_id order by payment_month) as group_id
	from rev_dif_table

),

-- calculation MRR
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

-- create and calculate finel table
select 
	r.user_id,
	gpu.game_name,
	gpu."language",
	gpu.age,
	d.max_date,
	d.min_date,
	r.first_month_day,
	r.payment_month,
	r.rev,
	r.month_dif,
	r.rev_dif,
	mrr.mrr_cumulative,
	
	-- calculate retention after churn (if month's difference more then 1 and month's difference in previous period = 1 then true)
	case
		when r.month_dif > 1 and lead(r.month_dif) over (partition by r.user_id order by r.payment_month) = 1
		then 1 else 0
	end as ret_af_ch,
	
	-- define mrr group: if difference between months = 1 and user payed more, then 2 times, then true. 
	-- If month's difference more then 1 but the next period is payment every month more, then 2, then true too
	case
		when ((r.month_dif isnull and  lead(r.month_dif) over (partition by r.user_id order by r.payment_month) = 1) or r.month_dif = 1) 
			or (r.month_dif > 1 and lead(r.month_dif) over (partition by r.user_id order by r.payment_month) = 1) 
		then 1 else 0
	end as mrr_group,
	
	-- define total mrr group: if the payment month is last and payment insist in the mrr group then true
	case
		when (r.payment_month = date_part('month', d.max_date) and lag(r.month_dif) over (partition by r.user_id order by r.payment_month) = 1)
			or (r.month_dif = 1 and lead(r.month_dif) over (partition by r.user_id order by r.payment_month) > 1)		
		then 1 else 0
	end as total_mrr_group,
	
	
	-- define new mrr group: for all first months or 1st month after returning
	case
		when (date_part('month', d.min_date) = r.payment_month or r.month_dif > 1) and lead(r.month_dif) over (partition by r.user_id order by r.payment_month) = 1
		then 1 else 0
	end as new_mrr_group
				
from rev_dif_table as r


left join mrr as mrr
	on r.user_id = mrr.user_id and r.payment_month = mrr.payment_month

left join dates_table as d
	on r.user_id = d.user_id

left join games_paid_users gpu  
	on r.user_id = gpu.user_id
