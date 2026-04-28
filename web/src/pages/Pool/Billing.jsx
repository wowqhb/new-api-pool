/*
Pool Management — 收支对账
- 期间切换：今日 / 7 天 / 30 天
- KPI: 收入 / 用户消耗 / 上游成本（按 PoolUpstreamCostRatio 估算）/ 毛利 / 毛利率
- 横向拆解：按模型 / 按分组
*/

import React, { useEffect, useState } from 'react';
import {
  Card,
  Row,
  Col,
  Spin,
  Tag,
  Typography,
  Button,
  Space,
  Table,
  Banner,
  Radio,
  RadioGroup,
} from '@douyinfe/semi-ui';
import { IconRefresh } from '@douyinfe/semi-icons';
import { useTranslation } from 'react-i18next';
import { API } from '../../helpers/api';
import { showError } from '../../helpers';
import PoolPageLayout from './Layout';

const { Text, Title } = Typography;

const KPICard = ({ label, value, suffix, tone = 'default' }) => {
  const toneColor = {
    default: 'var(--semi-color-text-0)',
    success: 'var(--semi-color-success)',
    warning: 'var(--semi-color-warning)',
    danger: 'var(--semi-color-danger)',
    primary: 'var(--semi-color-primary)',
  }[tone];
  return (
    <Card bodyStyle={{ padding: 16 }} className='!rounded-xl'>
      <Text type='tertiary' size='small'>
        {label}
      </Text>
      <div className='mt-1 flex items-baseline gap-1'>
        <span style={{ fontSize: 22, fontWeight: 600, color: toneColor }}>
          {value}
        </span>
        {suffix && (
          <span style={{ fontSize: 13, color: 'var(--semi-color-text-2)' }}>
            {suffix}
          </span>
        )}
      </div>
    </Card>
  );
};

const Billing = () => {
  const { t } = useTranslation();
  const [period, setPeriod] = useState('today');
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState(null);

  const fetchData = async (p = period) => {
    setLoading(true);
    try {
      const res = await API.get(`/api/pool/billing/summary?period=${p}`);
      if (res?.data?.success) {
        setData(res.data.data);
      } else {
        showError(res?.data?.message || t('加载失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData(period);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [period]);

  const modelColumns = [
    {
      title: t('模型'),
      dataIndex: 'model_name',
      render: (v) => <span className='font-mono text-xs'>{v || '-'}</span>,
    },
    { title: t('请求数'), dataIndex: 'requests' },
    {
      title: t('用户消耗 ($)'),
      dataIndex: 'consume_usd',
    },
    {
      title: t('上游成本 ($)'),
      dataIndex: 'upstream_usd',
      render: (v) => <Text type='warning'>{v}</Text>,
    },
    {
      title: t('毛利 ($)'),
      dataIndex: 'profit_usd',
      render: (v) => <Text type='success'>{v}</Text>,
    },
  ];

  const groupColumns = [
    {
      title: t('分组'),
      dataIndex: 'group',
      render: (v) => <Tag>{v || 'default'}</Tag>,
    },
    { title: t('请求数'), dataIndex: 'requests' },
    {
      title: t('用户消耗 ($)'),
      dataIndex: 'consume_usd',
    },
    {
      title: t('上游成本 ($)'),
      dataIndex: 'upstream_usd',
      render: (v) => <Text type='warning'>{v}</Text>,
    },
    {
      title: t('毛利 ($)'),
      dataIndex: 'profit_usd',
      render: (v) => <Text type='success'>{v}</Text>,
    },
  ];

  return (
    <PoolPageLayout
      title={t('收支对账')}
      subtitle={t('收入 / 上游成本 / 毛利、按模型与分组拆解')}
      badge='Billing'
      extra={
        <Space>
          <RadioGroup
            type='button'
            buttonSize='small'
            value={period}
            onChange={(e) => setPeriod(e.target.value)}
          >
            <Radio value='today'>{t('今日')}</Radio>
            <Radio value='7d'>{t('近 7 天')}</Radio>
            <Radio value='30d'>{t('近 30 天')}</Radio>
          </RadioGroup>
          <Button
            icon={<IconRefresh />}
            size='small'
            onClick={() => fetchData(period)}
            loading={loading}
          >
            {t('刷新')}
          </Button>
        </Space>
      }
    >
      <Banner
        type='info'
        description={t(
          '上游成本按"上游分成比例"近似估算（默认 60%）。若需更精确，请在系统配置中设置 PoolUpstreamCostRatio。',
        )}
        closeIcon={null}
        className='mb-3'
      />

      {loading ? (
        <div className='py-16 text-center'>
          <Spin size='middle' />
        </div>
      ) : (
        <>
          <Row gutter={[12, 12]}>
            <Col span={6}>
              <KPICard
                label={t('收入 (充值)')}
                value={`¥${data?.revenue ?? 0}`}
                tone='primary'
              />
            </Col>
            <Col span={6}>
              <KPICard
                label={t('用户消耗')}
                value={`$${data?.consume_usd ?? 0}`}
              />
            </Col>
            <Col span={6}>
              <KPICard
                label={t('上游成本（估算）')}
                value={`$${data?.upstream_cost ?? 0}`}
                tone='warning'
              />
            </Col>
            <Col span={6}>
              <KPICard
                label={t('毛利')}
                value={`$${data?.gross_profit ?? 0}`}
                suffix={`${data?.margin_percent ?? 0}%`}
                tone='success'
              />
            </Col>
          </Row>

          <div className='mt-6 grid gap-4 md:grid-cols-2'>
            <Card title={t('按模型 (Top 10)')}>
              <Table
                dataSource={data?.by_model || []}
                columns={modelColumns}
                rowKey='model_name'
                pagination={false}
                size='small'
              />
            </Card>
            <Card title={t('按分组 (Top 10)')}>
              <Table
                dataSource={data?.by_group || []}
                columns={groupColumns}
                rowKey='group'
                pagination={false}
                size='small'
              />
            </Card>
          </div>
        </>
      )}
    </PoolPageLayout>
  );
};

export default Billing;
