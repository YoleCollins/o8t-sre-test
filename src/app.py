import json
import boto3
import os
import logging
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize outside handler to reuse connections (helps with cold starts)
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('TABLE_NAME', 'llm_scores')
table = dynamodb.Table(table_name)

# Helper to handle Decimal serialization
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

def scan_table_with_pagination():
    """
    Scan table with pagination to handle larger datasets.
    Processes in batches of 100 to avoid timeouts.
    """
    items = []
    last_evaluated_key = None
    
    while True:
        scan_params = {'Limit': 100}
        if last_evaluated_key:
            scan_params['ExclusiveStartKey'] = last_evaluated_key
        
        response = table.scan(**scan_params)
        items.extend(response.get('Items', []))
        
        last_evaluated_key = response.get('LastEvaluatedKey')
        if not last_evaluated_key:
            break
    
    return items

def lambda_handler(event, context):
    """
    Lambda handler to retrieve LLM scores.
    Added pagination and better error handling.
    """
    logger.info(f"Request received: {event.get('path', 'unknown')}")

    try:
        items = scan_table_with_pagination()
        logger.info(f"Retrieved {len(items)} items")

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'  #Restrict this in prod
            },
            'body': json.dumps({
                'items': items,
                'count': len(items)
            }, cls=DecimalEncoder)
        }

    except Exception as e:
        logger.error(f"Error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': 'Internal Server Error',
                'message': str(e)  #Don't expose error details in prod
            })
        }