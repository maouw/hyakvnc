import logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
lh = logging.StreamHandler()
lh.setFormatter(logging.Formatter('%(levelname)s - %(message)s'))
logger.addHandler(lh)