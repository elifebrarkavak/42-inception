NAME		= inception

COMPOSE_DIR	= srcs
COMPOSE_FILE	= $(COMPOSE_DIR)/docker-compose.yml
ENV_FILE	= $(COMPOSE_DIR)/.env

DATA_PATH	:= $(shell grep -m1 '^DATA_PATH=' $(ENV_FILE) | cut -d '=' -f2)

COMPOSE		= docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE)


all: build up

data:
	@mkdir -p $(DATA_PATH)/mariadb
	@mkdir -p $(DATA_PATH)/wordpress

build: data
	$(COMPOSE) build

up: data
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

clean: down
	@docker system prune -af > /dev/null

fclean: clean
	@sudo rm -rf $(DATA_PATH)/mariadb
	@sudo rm -rf $(DATA_PATH)/wordpress

re: fclean all
