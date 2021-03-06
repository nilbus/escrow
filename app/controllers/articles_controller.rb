class ArticlesController < ApplicationController

	def new
	end

	def create
		@article = Article.new(article_params)
		@article.update_attribute(:total_bets, 0)
		@article.update_attribute(:creator_id, params[:creator_id])
		@article.update_attribute(:expired, false)
		@article_following = ArticleToFollower.new(article_id: @article.id, user_id: params[:creator_id])
		@article_following.save
		if @article.save
			redirect_to @article
		else
			render 'new'
		end
	end

	def show
		@article = Article.find(params[:id])
		check_expiration(@article)
		respond_to do |format|
			format.html
			format.json { render json: @article }
		end
	end

	def index
		@articles = Article.where(expired: false).sort_by { |article| article.created_at }.reverse
	end

	#because yes
	def bet_yes
		@article = Article.find(params[:article_id])
		@article_following = ArticleToFollower.new(article_id: @article.id, user_id: params[:active_user_id])
		@article_following.save
		@active_user = User.find(params[:active_user_id])
		if !(check_expiration(@article))
			@bet = Bet.new
			@bet.update_attribute(:user_id, params[:active_user_id])
			@bet.update_attribute(:article_id, @article.id)
			@bet.update_attribute(:is_yes, true)
			if (@active_user.balance - @article.min_bet >= 0)
				@active_user.update_attribute(:balance, @active_user.balance - @article.min_bet)
				@article.update_attribute(:yes_bet_total, @article.yes_bet_total + @article.min_bet)
				@article.update_attribute(:total_bets, @article.total_bets + @article.min_bet)
			end
		end
		respond_to do |format|
			@active_user = User.find(params[:active_user_id])
			#TODO this is really hacky, make the hashed attribute make sense
			@article["topic"] = @active_user.balance
			format.json{ render json: @article }
		end
	end

	def bet_no
		puts "bet no being called..."
		@article = Article.find(params[:article_id])
		@article_following = ArticleToFollower.new(article_id: @article.id, user_id: params[:active_user_id])
		if !(check_expiration(@article))
			@active_user = User.find(params[:active_user_id])
			@bet = Bet.new
			@bet.update_attribute(:user_id, params[:active_user_id])
			@bet.update_attribute(:article_id, @article.id)
			@bet.update_attribute(:is_yes, false)
			if (@active_user.balance - @article.min_bet >= 0)
				@active_user.update_attribute(:balance, @active_user.balance - @article.min_bet)
				@article.update_attribute(:no_bet_total, @article.no_bet_total + @article.min_bet)
				@article.update_attribute(:total_bets, @article.total_bets + @article.min_bet)
			end
		end
		respond_to do |format|
			@active_user = User.find(params[:active_user_id])
			#TODO this is really hacky, make the hashed attribute make sense
			@article["topic"] = @active_user.balance
			format.json{ render json: @article }
		end
	end

	def check_expiration(article)
		if (article.expired?)
			return true
		end
		if (DateTime.current.to_i - article.created_at.to_i > article.time_to_expiration)
			article.update_attribute(:expired, true)
			if (article.yes_bet_total > article.no_bet_total)
				article.update_attribute(:winning_side, "yes")
			end
			if (article.yes_bet_total < article.no_bet_total)
				article.update_attribute(:winning_side, "no")
			end
			set_winnings_per_winner(article)
		end
		return article.expired?
	end

	def check_expiration_all
		evaluate_user_bets
		ArticleToFollower.where(user_id: current_user.id).each do |articleToFollower|
			article_id = articleToFollower.article_id
			check_expiration(Article.find(article_id))
		end
		render :nothing => true, :status => 200, :content_type => 'text/html'
	end

	def get_user_balance(user_id)
		return User.find(user_id).balance
	end

	def evaluate_user_bets
		puts "debug evaluating"
		user = current_user
		Bet.where({user_id: user.id, was_evaluated: false}).each do |bet|
			"debug iterating on bets " + bet.id.to_s
			article = Article.find(bet.article_id)
			puts "debug in here"
			if (article.expired?)
				is_winning_bet = ((bet.is_yes && article.winning_side == "yes") || (!bet.is_yes && article.winning_side == "no"))
				puts "debug is_winning bet " + is_winning_bet.to_s
				if (article.winning_side == "draw" or is_winning_bet)
					@user = User.find(user.id)
					puts("debug *****USER GETTING PAID: " + @user.id.to_s)
					puts("debug *****USER BALANCE BEFORE " + @user.balance.to_s)
					@user.update_attribute(:balance, @user.balance + article.winnings_per_winner)
					puts("debug *****USER BALANCE after " + @user.balance.to_s)
				end
				bet.update_attribute(:was_evaluated, true)
			end
		end
	end

	private
	def article_params
		params.require(:article).permit(:title, :min_bet, :time_to_expiration, :topic)
	end

	def set_winnings_per_winner(article)
		if (article.winning_side == "yes")
			number_of_winning_bets = article.yes_bet_total / article.min_bet
			puts("*********number bets = " + number_of_winning_bets.to_s)
		else
			if (article.winning_side == "no")
				number_of_winning_bets = article.no_bet_total / article.min_bet
			else
				# it's a draw
				number_of_winning_bets = article.total_bets / article.min_bet
			end
		end
		winnings_per_winner = article.total_bets / number_of_winning_bets
		article.update_attribute(:winnings_per_winner, winnings_per_winner)
		puts("debug *****WINNINGS PER WINNER" + winnings_per_winner.to_s)
	end

end
