/*
Pool Management — 总览
拉 /api/pool/overview，展示健康分、账号数、今日吞吐/失败/利润 + 各分组健康度。
当前后端返回 stub 全 0，前端正常渲染为占位。
*/

import React, { useEffect, useState } from 'react';
import { Card, Row, Col, Spin, Tag, Typography, Button, Space } from '@douyinfe/semi-ui';
import { IconRefresh } from '@douyinfe/semi-icons';
import { useTranslation } from 'react-i18next';
import { API } from '../../helpers/api';
import { showError } from '../../helpers';
import PoolPageLayout from './Layout';

const { Text, Title } = Typography;

const StatCard = ({ label, value, suffix = '', tone = 'default' }) => {
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

const Overview = () => {
  const { t } = useTranslation();
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState(null);

  const fetchOverview = async () => {
    setLoading(true);
    try {
      const res = await API.get('/api/pool/overview');
      if (res?.data?.success) {
        setData(res.data.data);
      } else {
        showError(res?.data?.message || t('加载号池总览失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchOverview();
  }, []);

  return (
    <PoolPageLayout
      title={t('号池总览')}
      subtitle={t('号池健康度、今日吞吐与利润、各分组实时状态')}
      badge={t('Live')}
      extra={
        <Button
          icon={<IconRefresh />}
          size='small'
          onClick={fetchOverview}
          loading={loading}
        >
          {t('刷新')}
        </Button>
      }
    >
      {loading ? (
        <div className='py-16 text-center'>
          <Spin size='middle' />
        </div>
      ) : (
        <>
          <Row gutter={[12, 12]}>
            <Col span={6}>
              <StatCard
                label={t('健康分')}
                value={data?.health_score ?? 0}
                suffix='/ 100'
                tone={
                  (data?.health_score ?? 0) >= 80
                    ? 'success'
                    : (data?.health_score ?? 0) >= 60
                    ? 'warning'
                    : 'danger'
                }
              />
            </Col>
            <Col span={6}>
              <StatCard
                label={t('上游账号在线')}
                value={data?.accounts_active ?? 0}
                suffix={`/ ${data?.accounts_total ?? 0}`}
                tone='success'
              />
            </Col>
            <Col span={6}>
              <StatCard
                label={t('告警账号')}
                value={data?.accounts_warning ?? 0}
                tone='warning'
              />
            </Col>
            <Col span={6}>
              <StatCard
                label={t('禁用账号')}
                value={data?.accounts_disabled ?? 0}
                tone='danger'
              />
            </Col>
          </Row>

          {/* 渠道状态 */}
          <div className='mt-4'>
            <Row gutter={[12, 12]}>
              <Col span={8}>
                <StatCard
                  label={t('渠道总数')}
                  value={data?.channels_total ?? 0}
                />
              </Col>
              <Col span={8}>
                <StatCard
                  label={t('已启用渠道')}
                  value={data?.channels_enabled ?? 0}
                  tone='success'
                />
              </Col>
              <Col span={8}>
                <StatCard
                  label={t('禁用 / 异常渠道')}
                  value={data?.channels_disabled ?? 0}
                  tone='danger'
                />
              </Col>
            </Row>
          </div>

          {/* 今日 */}
          <div className='mt-6'>
            <Title heading={6} style={{ marginBottom: 8 }}>
              {t('今日')}
            </Title>
            <Row gutter={[12, 12]}>
              <Col span={6}>
                <StatCard label={t('请求数')} value={data?.today_requests ?? 0} />
              </Col>
              <Col span={6}>
                <StatCard
                  label={t('成功 / 失败')}
                  value={`${data?.today_success ?? 0} / ${data?.today_failure ?? 0}`}
                />
              </Col>
              <Col span={6}>
                <StatCard
                  label={t('收入')}
                  value={`$${data?.today_revenue ?? 0}`}
                  tone='primary'
                />
              </Col>
              <Col span={6}>
                <StatCard
                  label={t('利润')}
                  value={`$${data?.today_profit ?? 0}`}
                  tone='success'
                />
              </Col>
            </Row>
          </div>

          {/* 分组 */}
          <div className='mt-6'>
            <Title heading={6} style={{ marginBottom: 8 }}>
              {t('分组实况')}
            </Title>
            <Row gutter={[12, 12]}>
              {(data?.groups || []).map((g) => (
                <Col span={8} key={g.name}>
                  <Card bodyStyle={{ padding: 16 }} className='!rounded-xl'>
                    <div className='flex items-center justify-between'>
                      <Text strong>{g.name}</Text>
                      <Tag size='small' color='blue'>
                        {g.channels} {t('渠道')}
                      </Tag>
                    </div>
                    <div className='mt-2 grid grid-cols-3 gap-2 text-xs text-gray-500'>
                      <div>
                        RPM <span className='text-gray-900 font-medium'>{g.rpm}</span>
                      </div>
                      <div>
                        TPM <span className='text-gray-900 font-medium'>{g.tpm}</span>
                      </div>
                      <div>
                        {t('失败率')}{' '}
                        <span className='text-gray-900 font-medium'>
                          {g.fail_rate}%
                        </span>
                      </div>
                    </div>
                  </Card>
                </Col>
              ))}
            </Row>
          </div>
        </>
      )}
    </PoolPageLayout>
  );
};

export default Overview;
