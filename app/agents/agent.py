# app/agents/agent.py
from app.agents.adk_agents import generator_agent, reviewer_agent

# The ADK Web server ONLY wants the Agent definition. 
# It handles the Runner and sessions automatically!
# root_agent = generator_agent
root_agent = reviewer_agent